import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "Voteaxis — See where you stand";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpenGraphImage() {
  // The 192px mark, not the 1024px source: it renders at 72px here, and the
  // file is base64-inlined into the Satori payload at build time.
  const markData = await readFile(
    join(process.cwd(), "public/brand/icon-192.png"),
  );
  const markSrc = `data:image/png;base64,${markData.toString("base64")}`;

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        flexDirection: "column",
        justifyContent: "space-between",
        padding: 56,
        background:
          "linear-gradient(160deg, #c5d0e0 0%, #e8eef6 55%, #dce5f0 100%)",
        color: "#07111f",
      }}
    >
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          {/* biome-ignore lint/performance/noImgElement: ImageResponse renders
              through Satori at build time, which supports <img> only — next/image
              is a client runtime component and cannot be used here. */}
          <img
            src={markSrc}
            width={72}
            height={72}
            style={{ borderRadius: 16 }}
            alt=""
          />
          <span
            style={{
              fontSize: 34,
              fontWeight: 800,
              letterSpacing: -1.5,
            }}
          >
            Voteaxis
          </span>
        </div>
        <span style={{ fontSize: 18, opacity: 0.65, fontWeight: 600 }}>
          SII v1
        </span>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 22 }}>
        <div
          style={{
            fontSize: 64,
            fontWeight: 800,
            lineHeight: 0.95,
            letterSpacing: -2.5,
            maxWidth: 980,
          }}
        >
          See where you stand. Choose who to vote for.
        </div>
        <div
          style={{
            display: "flex",
            height: 22,
            width: "100%",
            overflow: "hidden",
            borderRadius: 999,
          }}
        >
          <div style={{ flex: 1, background: "#1a56e8" }} />
          <div style={{ flex: 1, background: "#e23a28" }} />
        </div>
      </div>
    </div>,
    { ...size },
  );
}
