import type { MetadataRoute } from "next";
import { absoluteUrl } from "@/lib/site";

/**
 * Indexable routes only. /contribute/thanks is a post-checkout receipt page and
 * is noindex in its own metadata, so it stays out of here.
 */
export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();

  return [
    {
      url: absoluteUrl("/"),
      lastModified,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: absoluteUrl("/methodology"),
      lastModified,
      changeFrequency: "monthly",
      priority: 0.7,
    },
    {
      url: absoluteUrl("/contribute"),
      lastModified,
      changeFrequency: "monthly",
      priority: 0.6,
    },
  ];
}
