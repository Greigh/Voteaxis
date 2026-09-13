import { serializeJsonLd } from "@/lib/structured-data";

/**
 * Renders a schema.org graph as a native <script type="application/ld+json">.
 * next/script is for executable JavaScript; structured data is not that.
 */
export function JsonLd({ data }: { data: Record<string, unknown> }) {
  return (
    // The only way to emit a JSON-LD payload. serializeJsonLd escapes `<`, so
    // a value carrying markup cannot close the script tag early.
    <script
      type="application/ld+json"
      // biome-ignore lint/security/noDangerouslySetInnerHtml: JSON-LD has no other emit path; serializeJsonLd escapes `<`.
      dangerouslySetInnerHTML={{ __html: serializeJsonLd(data) }}
    />
  );
}
