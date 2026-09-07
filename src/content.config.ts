import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const books = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/books' }),
  schema: ({ image }) =>
    z.object({
      title: z.string(),
      series: z.string(),
      order: z.number(),
      releaseYear: z.number(),
      tropes: z.array(z.string()),
      blurb: z.string(),
      amazon: z.string().url(),
      goodreads: z.string().url(),
      cover: image(),
      excerpt: z.string(),
    }),
});

const articles = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/articles' }),
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    excerpt: z.string(),
    tags: z.array(z.string()).default([]),
  }),
});

export const collections = { books, articles };
