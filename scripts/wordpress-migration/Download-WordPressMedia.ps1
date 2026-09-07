<#
.SYNOPSIS
    Downloads every media attachment from a WordPress export (WXR) and renames
    each file to match the post, page, or custom-post-type item it belongs to.

.DESCRIPTION
    WordPress "Export All Content" splits large sites into several WXR (XML)
    files - typically one for media, one for posts, one for each custom post
    type (e.g. "book"). This script accepts any number of those files, merges
    them, and:

      1. Splits every <item> into "media" (wp:post_type = attachment) and
         "content" (everything else: post, page, book, etc.).
      2. For each media item, works out which piece of content it belongs to,
         trying in order:
           a) wp:post_parent (the "Uploaded to" post in the Media Library)
           b) the post/page whose _thumbnail_id postmeta points at it
              (i.e. it's used as a Featured Image)
           c) a post/page whose content:encoded body references the
              attachment by id - "wp-image-<id>" or "id":<id> - which is how
              the block editor (Gutenberg) embeds images
           d) a post/page whose content:encoded body references the file's
              original filename (classic-editor <img src="..."> embeds)
         Anything that still can't be matched is filed under "Unattached".
      3. Downloads the file and saves it as "<Content Title>[-N].<ext>",
         numbering duplicates so multiple images for the same post don't
         collide.
      4. Writes a CSV log recording the original URL, the match method used,
         and the final filename, so ambiguous or unattached files can be
         reviewed and fixed up by hand afterwards.

.PARAMETER Path
    One or more paths to WXR .xml files, and/or folders containing them
    (folders are scanned non-recursively for *.xml). Defaults to the current
    directory.

.PARAMETER OutputFolder
    Where downloaded, renamed files are written. Created if it doesn't exist.
    Defaults to ".\wordpress-media".

.PARAMETER LogFile
    Path for the CSV summary log. Defaults to "media-download-log.csv" inside
    OutputFolder.

.PARAMETER Force
    Re-download and overwrite files that already exist in OutputFolder.
    Without this switch, existing files are left alone (safe to re-run).

.PARAMETER DelayMilliseconds
    Pause between downloads, to avoid hammering the source site. Default 150ms.

.PARAMETER MaxRetries
    Number of attempts per file before it's logged as Failed. Default 3.

.EXAMPLE
    .\Download-WordPressMedia.ps1 -Path .\rebeccaraine.WordPress.20260907.media.xml, `
        .\rebeccaraine.WordPress.20260907.posts.xml, `
        .\rebeccaraine.WordPress.20260907.xml `
        -OutputFolder .\wordpress-media

.EXAMPLE
    # Drop all three exported .xml files in one folder and just point at it
    .\Download-WordPressMedia.ps1 -Path .\wxr-exports -OutputFolder .\wordpress-media -Force
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string[]]$Path = @('.'),

    [string]$OutputFolder = '.\wordpress-media',

    [string]$LogFile,

    [switch]$Force,

    [int]$DelayMilliseconds = 150,

    [int]$MaxRetries = 3
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Get-SafeFileName {
    param(
        [string]$Name,
        [int]$MaxLength = 80
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = 'Untitled' }
    $clean = $Name -replace '[<>:"/\\|?*]', ''
    $clean = $clean -replace '\s+', '-'
    $clean = $clean -replace '-{2,}', '-'
    $clean = $clean.Trim('-', '.', ' ')
    if ($clean.Length -gt $MaxLength) { $clean = $clean.Substring(0, $MaxLength).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'Untitled' }
    return $clean
}

# ---------------------------------------------------------------------------
# 1. Resolve the set of WXR files to read
# ---------------------------------------------------------------------------
$xmlFiles = foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Filter '*.xml' -File
    }
    elseif (Test-Path -LiteralPath $p -PathType Leaf) {
        Get-Item -LiteralPath $p
    }
    else {
        Write-Warning "Path not found, skipping: $p"
    }
}
$xmlFiles = @($xmlFiles | Sort-Object FullName -Unique)
if (-not $xmlFiles) {
    throw "No WordPress export .xml files were found under: $($Path -join ', ')"
}

Write-Host "Found $($xmlFiles.Count) export file(s):" -ForegroundColor Cyan
$xmlFiles | ForEach-Object { Write-Host "  $($_.FullName)" }

# ---------------------------------------------------------------------------
# 2. Parse every <item> out of every file
# ---------------------------------------------------------------------------
$allItems = [System.Collections.Generic.List[object]]::new()
foreach ($file in $xmlFiles) {
    try {
        [xml]$xml = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    }
    catch {
        Write-Warning "Could not parse $($file.FullName): $_"
        continue
    }
    foreach ($i in @($xml.rss.channel.item)) {
        if ($i) { $allItems.Add($i) }
    }
}
Write-Host "Parsed $($allItems.Count) total <item> entries." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 3. Split into media items vs. content items
# ---------------------------------------------------------------------------
$mediaItems = [System.Collections.Generic.List[object]]::new()
$contentItems = [System.Collections.Generic.List[object]]::new()
foreach ($item in $allItems) {
    if ([string]$item.'wp:post_type' -eq 'attachment') { $mediaItems.Add($item) }
    else { $contentItems.Add($item) }
}
Write-Host "  Media (attachment) items                  : $($mediaItems.Count)"
Write-Host "  Content items (posts / pages / book, etc.) : $($contentItems.Count)"

if ($mediaItems.Count -eq 0) {
    throw "No attachment items (wp:post_type = attachment) were found. Did you include the media export file?"
}

# ---------------------------------------------------------------------------
# 4. Build lookup tables: post_id -> content title, and featured-image links
# ---------------------------------------------------------------------------
$contentById = @{}
$thumbnailOwner = @{}   # attachment post_id -> owning content post_id

foreach ($c in $contentItems) {
    $id = [string]$c.'wp:post_id'
    if ([string]::IsNullOrWhiteSpace($id)) { continue }

    $title = [string]$c.title
    if ([string]::IsNullOrWhiteSpace($title)) { $title = "untitled-$id" }

    $contentById[$id] = [PSCustomObject]@{
        Id       = $id
        Title    = $title
        PostType = [string]$c.'wp:post_type'
        Body     = [string]$c.'content:encoded'
    }

    foreach ($m in @($c.'wp:postmeta')) {
        if (-not $m) { continue }
        if ([string]$m.'wp:meta_key' -eq '_thumbnail_id') {
            $thumbId = [string]$m.'wp:meta_value'
            if ($thumbId) { $thumbnailOwner[$thumbId] = $id }
        }
    }
}
Write-Host "Indexed $($contentById.Count) content items and $($thumbnailOwner.Count) featured-image links." -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 5. Work out which content item each media file belongs to, and its new name
# ---------------------------------------------------------------------------
$plan = [System.Collections.Generic.List[object]]::new()
$nameCounts = @{}

foreach ($m in $mediaItems) {
    $id = [string]$m.'wp:post_id'
    $url = [string]$m.'wp:attachment_url'
    if ([string]::IsNullOrWhiteSpace($url)) { $url = [string]$m.guid }
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-Warning "Media item $id has no URL, skipping."
        continue
    }

    $originalName = $url.Split('/')[-1].Split('?')[0]
    $ext = [System.IO.Path]::GetExtension($originalName)

    $parentId = [string]$m.'wp:post_parent'
    $matchTitle = $null
    $matchMethod = 'unattached'
    $matchCount = 0

    if ($parentId -and $parentId -ne '0' -and $contentById.ContainsKey($parentId)) {
        $matchTitle = $contentById[$parentId].Title
        $matchMethod = 'post_parent'
        $matchCount = 1
    }
    elseif ($thumbnailOwner.ContainsKey($id) -and $contentById.ContainsKey($thumbnailOwner[$id])) {
        $matchTitle = $contentById[$thumbnailOwner[$id]].Title
        $matchMethod = 'featured-image'
        $matchCount = 1
    }
    else {
        # Gutenberg block editor embeds images by attachment id, e.g.
        # class="wp-image-834" or "wp:image {"id":834}"
        $idNeedle1 = "wp-image-$id"
        $idNeedle2 = "`"id`":$id"
        $hits = [System.Collections.Generic.List[object]]::new()
        foreach ($c in $contentById.Values) {
            if ($c.Body -and ($c.Body.Contains($idNeedle1) -or $c.Body.Contains($idNeedle2))) { $hits.Add($c) }
        }
        if ($hits.Count -gt 0) {
            $matchTitle = $hits[0].Title
            $matchMethod = if ($hits.Count -gt 1) { 'content-match-id (ambiguous)' } else { 'content-match-id' }
            $matchCount = $hits.Count
        }
        else {
            # Classic editor embeds the image by filename in an <img src="...">
            $hits = [System.Collections.Generic.List[object]]::new()
            foreach ($c in $contentById.Values) {
                if ($c.Body -and $c.Body.Contains($originalName)) { $hits.Add($c) }
            }
            if ($hits.Count -gt 0) {
                $matchTitle = $hits[0].Title
                $matchMethod = if ($hits.Count -gt 1) { 'content-match-filename (ambiguous)' } else { 'content-match-filename' }
                $matchCount = $hits.Count
            }
        }
    }

    if (-not $matchTitle) { $matchTitle = 'Unattached' }
    $safeTitle = Get-SafeFileName -Name $matchTitle

    if ($nameCounts.ContainsKey($safeTitle)) {
        $nameCounts[$safeTitle]++
        $newBaseName = "$safeTitle-$($nameCounts[$safeTitle])"
    }
    else {
        $nameCounts[$safeTitle] = 1
        $newBaseName = $safeTitle
    }

    $plan.Add([PSCustomObject]@{
            AttachmentId = $id
            OriginalUrl  = $url
            OriginalName = $originalName
            MatchedTitle = $matchTitle
            MatchMethod  = $matchMethod
            MatchCount   = $matchCount
            NewFileName  = "$newBaseName$ext"
        })
}

# ---------------------------------------------------------------------------
# 6. Download everything according to the plan
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}
if (-not $LogFile) { $LogFile = Join-Path $OutputFolder 'media-download-log.csv' }

$results = [System.Collections.Generic.List[object]]::new()
$i = 0
foreach ($p in $plan) {
    $i++
    $dest = Join-Path $OutputFolder $p.NewFileName
    Write-Progress -Activity 'Downloading WordPress media' -Status $p.NewFileName -PercentComplete (($i / $plan.Count) * 100)

    $status = 'Skipped (exists)'
    if ($Force -or -not (Test-Path -LiteralPath $dest)) {
        if ($PSCmdlet.ShouldProcess($p.OriginalUrl, "Download to $dest")) {
            $attempt = 0
            $success = $false
            do {
                $attempt++
                try {
                    Invoke-WebRequest -Uri $p.OriginalUrl -OutFile $dest -UseBasicParsing
                    $success = $true
                }
                catch {
                    if ($attempt -ge $MaxRetries) {
                        Write-Warning "FAILED ($attempt/$MaxRetries) $($p.OriginalUrl): $_"
                    }
                    else {
                        Start-Sleep -Milliseconds (500 * $attempt)
                    }
                }
            } while (-not $success -and $attempt -lt $MaxRetries)

            $status = if ($success) { 'Downloaded' } else { 'Failed' }
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
        else {
            $status = 'WhatIf'
        }
    }

    $results.Add([PSCustomObject]@{
            AttachmentId = $p.AttachmentId
            OriginalUrl  = $p.OriginalUrl
            OriginalName = $p.OriginalName
            NewFileName  = $p.NewFileName
            MatchedTitle = $p.MatchedTitle
            MatchMethod  = $p.MatchMethod
            MatchCount   = $p.MatchCount
            Status       = $status
        })
}
Write-Progress -Activity 'Downloading WordPress media' -Completed

# ---------------------------------------------------------------------------
# 7. Log + summary
# ---------------------------------------------------------------------------
$results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8

$downloaded = @($results | Where-Object Status -eq 'Downloaded').Count
$skipped = @($results | Where-Object Status -eq 'Skipped (exists)').Count
$failed = @($results | Where-Object Status -eq 'Failed').Count
$unattached = @($results | Where-Object MatchMethod -eq 'unattached').Count
$ambiguous = @($results | Where-Object { $_.MatchMethod -match 'ambiguous' }).Count

Write-Host ''
Write-Host '==================== Summary ====================' -ForegroundColor Green
Write-Host "Total media items     : $($results.Count)"
Write-Host "Downloaded            : $downloaded"
Write-Host "Already existed       : $skipped"
Write-Host "Failed                : $failed"
Write-Host "Unattached (no match) : $unattached"
Write-Host "Ambiguous matches     : $ambiguous"
Write-Host "Log written to        : $LogFile"
Write-Host '===================================================' -ForegroundColor Green

if ($failed -gt 0) {
    Write-Warning "$failed file(s) failed to download - see '$LogFile' (Status = Failed)."
}
if ($unattached -gt 0 -or $ambiguous -gt 0) {
    Write-Warning "$unattached unattached + $ambiguous ambiguous file(s) may need a manual rename - see '$LogFile' (MatchMethod column)."
}
