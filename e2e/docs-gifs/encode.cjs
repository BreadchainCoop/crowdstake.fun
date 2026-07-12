/* Encodes captured frames into the /docs GIFs with gifenc (pure JS — no
 * ffmpeg): one global palette per flow (sampled across frames) plus an
 * inter-frame transparency diff (dispose:1), which keeps mostly-static UI
 * walkthroughs small. Reads scaled/<flow>/*.png, writes out/<flow>.gif. */
const fs = require("fs");
const path = require("path");
const { PNG } = require("pngjs");
const { GIFEncoder, quantize, applyPalette } = require("gifenc");

const SCALED = path.join(__dirname, "scaled");
const OUT = path.join(__dirname, "out");
fs.mkdirSync(OUT, { recursive: true });

const only = process.env.FLOWS || process.argv[2];
const flows = only
  ? only.split(",")
  : fs.readdirSync(SCALED).filter((f) => !f.startsWith("."));

for (const flow of flows) {
  const dir = path.join(SCALED, flow);
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".png"))
    .sort();
  if (!files.length) {
    console.log(flow, "— no frames, skipped");
    continue;
  }
  const frames = files.map((f) =>
    PNG.sync.read(fs.readFileSync(path.join(dir, f))),
  );
  const { width: w, height: h } = frames[0];

  // Global palette from a sample across frames (every 3rd frame, every 4th px).
  const sampleParts = [];
  for (let i = 0; i < frames.length; i += 3) {
    const d = frames[i].data;
    const part = new Uint8ClampedArray(Math.ceil(d.length / 16) * 4);
    for (let p = 0, q = 0; p < d.length; p += 16, q += 4) {
      part[q] = d[p];
      part[q + 1] = d[p + 1];
      part[q + 2] = d[p + 2];
      part[q + 3] = 255;
    }
    sampleParts.push(part);
  }
  const sample = new Uint8ClampedArray(
    sampleParts.reduce((a, p) => a + p.length, 0),
  );
  let off = 0;
  for (const p of sampleParts) {
    sample.set(p, off);
    off += p.length;
  }
  const palette = quantize(sample, 255);
  const T = palette.length; // transparent slot
  const fullPalette = [...palette, [0, 0, 0]];

  const gif = GIFEncoder();
  let prev = null;
  for (const png of frames) {
    const rgba = new Uint8ClampedArray(png.data);
    const index = applyPalette(rgba, palette);
    if (!prev) {
      gif.writeFrame(index, w, h, { palette: fullPalette, delay: 167 });
    } else {
      const diff = new Uint8Array(index.length);
      let changed = 0;
      for (let i = 0; i < index.length; i++) {
        if (index[i] === prev[i]) diff[i] = T;
        else {
          diff[i] = index[i];
          changed++;
        }
      }
      gif.writeFrame(changed ? diff : index, w, h, {
        palette: fullPalette,
        delay: 167,
        transparent: true,
        transparentIndex: T,
        dispose: 1,
      });
    }
    prev = index;
  }
  gif.finish();
  const out = path.join(OUT, `${flow}.gif`);
  fs.writeFileSync(out, Buffer.from(gif.bytes()));
  console.log(
    flow,
    frames.length,
    "frames",
    Math.round(fs.statSync(out).size / 1024) + "KB",
  );
}
