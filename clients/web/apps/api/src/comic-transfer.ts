import { deflateSync, inflateRawSync, inflateSync } from 'node:zlib';

export type ImageFile = { name: string; bytes: Buffer };

export interface ComicInfoMetadata {
  title?: string;
  series?: string;
  number?: string;
  summary?: string;
  writer?: string;
  genre?: string;
  web?: string;
  manga?: boolean;
  pageCount?: number;
}

const invalid = () =>
  Object.assign(new Error('Invalid comic archive'), {
    code: 'BAD_REQUEST',
    statusCode: 400,
    publicError: true,
  });

const crcTable = Uint32Array.from({ length: 256 }, (_, n) => {
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n >>> 0;
});

const crc32 = (data: Buffer) => {
  let crc = 0xffffffff;
  for (const byte of data) crc = crcTable[(crc ^ byte) & 255]! ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
};

function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function unescapeXml(value: string): string {
  return value
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

export function buildComicInfoXml(meta: ComicInfoMetadata): Buffer {
  const tag = (name: string, val?: string | number) =>
    val !== undefined && String(val).trim() ? `  <${name}>${escapeXml(String(val).trim())}</${name}>\n` : '';
  const xml =
    `<?xml version="1.0" encoding="utf-8"?>\n` +
    `<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n` +
    tag('Title', meta.title) +
    tag('Series', meta.series) +
    tag('Number', meta.number) +
    tag('Summary', meta.summary) +
    tag('Writer', meta.writer) +
    tag('Genre', meta.genre) +
    tag('Web', meta.web) +
    tag('PageCount', meta.pageCount) +
    (meta.manga ? `  <Manga>YesAndRightToLeft</Manga>\n` : '') +
    `</ComicInfo>\n`;
  return Buffer.from(xml, 'utf8');
}

export function parseComicInfoXml(xmlBytes: Buffer): ComicInfoMetadata {
  const xml = xmlBytes.toString('utf8');
  const pick = (name: string) => {
    const match = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`, 'i').exec(xml);
    return match?.[1] ? unescapeXml(match[1].trim()) : undefined;
  };
  return {
    title: pick('Title') ?? pick('Series'),
    series: pick('Series'),
    number: pick('Number'),
    summary: pick('Summary'),
    writer: pick('Writer'),
    genre: pick('Genre'),
    web: pick('Web'),
  };
}

export function imageExtension(bytes: Buffer): 'png' | 'jpg' | 'gif' | 'webp' {
  if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'png';
  if (bytes[0] === 255 && bytes[1] === 216) return 'jpg';
  if (bytes.subarray(0, 3).toString() === 'GIF') return 'gif';
  if (bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP') return 'webp';
  throw invalid();
}

export function createCbz(images: Buffer[], metadata?: ComicInfoMetadata): Buffer {
  if (!images.length || images.length > 20000 || images.reduce((n, b) => n + b.length, 0) > 256 * 1024 * 1024) {
    throw invalid();
  }
  const files: ImageFile[] = images.map((bytes, index) => ({
    name: `${String(index + 1).padStart(6, '0')}.${imageExtension(bytes)}`,
    bytes,
  }));
  if (metadata && (metadata.title || metadata.series || metadata.summary || metadata.writer || metadata.genre)) {
    files.unshift({
      name: 'ComicInfo.xml',
      bytes: buildComicInfoXml({ ...metadata, pageCount: images.length }),
    });
  }
  return createArchive(files);
}

export function createArchive(files: ImageFile[]): Buffer {
  const locals: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  files.forEach(({ bytes, name: fileName }) => {
    const name = Buffer.from(fileName, 'utf8');
    const crc = crc32(bytes);
    const local = Buffer.alloc(30);
    const entry = Buffer.alloc(46);
    local.writeUInt32LE(0x04034b50);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6); // UTF-8 filename flag
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(bytes.length, 18);
    local.writeUInt32LE(bytes.length, 22);
    local.writeUInt16LE(name.length, 26);
    entry.writeUInt32LE(0x02014b50);
    entry.writeUInt16LE(20, 4);
    entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(0x0800, 8); // UTF-8 filename flag
    entry.writeUInt32LE(crc, 16);
    entry.writeUInt32LE(bytes.length, 20);
    entry.writeUInt32LE(bytes.length, 24);
    entry.writeUInt16LE(name.length, 28);
    entry.writeUInt32LE(offset, 42);
    locals.push(local, name, bytes);
    central.push(entry, name);
    offset += local.length + name.length + bytes.length;
  });
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}

export function readCbzWithMetadata(archive: Buffer): { files: ImageFile[]; metadata?: ComicInfoMetadata } {
  if (archive.length > 256 * 1024 * 1024) throw invalid();
  let end = -1;
  for (let at = archive.length - 22; at >= Math.max(0, archive.length - 65557); at--) {
    if (archive.readUInt32LE(at) === 0x06054b50) {
      end = at;
      break;
    }
  }
  if (end < 0 || archive.readUInt16LE(end + 4) || archive.readUInt16LE(end + 6)) throw invalid();
  const count = archive.readUInt16LE(end + 10);
  const directorySize = archive.readUInt32LE(end + 12);
  let cursor = archive.readUInt32LE(end + 16);
  let total = 0;
  const files: ImageFile[] = [];
  let metadata: ComicInfoMetadata | undefined;
  const names = new Set<string>();
  if (!count || count > 20000 || cursor + directorySize !== end) throw invalid();

  for (let index = 0; index < count; index++) {
    if (cursor + 46 > end || archive.readUInt32LE(cursor) !== 0x02014b50) throw invalid();
    const flags = archive.readUInt16LE(cursor + 8);
    const method = archive.readUInt16LE(cursor + 10);
    const crc = archive.readUInt32LE(cursor + 16);
    const compressed = archive.readUInt32LE(cursor + 20);
    const size = archive.readUInt32LE(cursor + 24);
    const nameLength = archive.readUInt16LE(cursor + 28);
    const extraLength = archive.readUInt16LE(cursor + 30);
    const commentLength = archive.readUInt16LE(cursor + 32);
    const localOffset = archive.readUInt32LE(cursor + 42);
    if (cursor + 46 + nameLength + extraLength + commentLength > end || flags & 1 || ![0, 8].includes(method)) {
      throw invalid();
    }
    const name = archive.subarray(cursor + 46, cursor + 46 + nameLength).toString('utf8');
    cursor += 46 + nameLength + extraLength + commentLength;
    if (
      !name ||
      name.length > 512 ||
      name.includes('\\') ||
      name.startsWith('/') ||
      /^[A-Za-z]:/.test(name) ||
      name.split('/').some((part) => part === '..') ||
      names.has(name)
    ) {
      throw invalid();
    }
    names.add(name);
    if (name.endsWith('/')) continue;

    const extractEntry = () => {
      if (size > 20 * 1024 * 1024 || (total += size) > 256 * 1024 * 1024 || size > Math.max(compressed, 1) * 200) {
        throw invalid();
      }
      if (localOffset + 30 > archive.length || archive.readUInt32LE(localOffset) !== 0x04034b50) throw invalid();
      const start = localOffset + 30 + archive.readUInt16LE(localOffset + 26) + archive.readUInt16LE(localOffset + 28);
      if (start + compressed > end) throw invalid();
      const encoded = archive.subarray(start, start + compressed);
      const bytes = method === 0 ? Buffer.from(encoded) : inflateRawSync(encoded, { maxOutputLength: size });
      if (bytes.length !== size || crc32(bytes) !== crc) throw invalid();
      return bytes;
    };

    if (/(?:^|\/)ComicInfo\.xml$/i.test(name) && size <= 512 * 1024) {
      try {
        metadata = parseComicInfoXml(extractEntry());
      } catch {
        // Ignore non-critical ComicInfo parse issue
      }
      continue;
    }
    if (!/\.(?:png|jpe?g|webp|gif)$/i.test(name)) continue;
    const bytes = extractEntry();
    imageExtension(bytes);
    files.push({ name, bytes });
  }
  if (!files.length) throw invalid();
  return {
    files: files.sort((a, b) => a.name.localeCompare(b.name, 'en', { numeric: true })),
    metadata,
  };
}

export function readCbz(archive: Buffer): ImageFile[] {
  return readCbzWithMetadata(archive).files;
}

function jpegSize(bytes: Buffer) {
  if (bytes[0] !== 255 || bytes[1] !== 216) throw invalid();
  let at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at++] !== 255) throw invalid();
    let marker = bytes[at++];
    while (marker === 255) marker = bytes[at++];
    if (marker === 217 || marker === 218) break;
    const length = bytes.readUInt16BE(at);
    if (length < 2 || at + length > bytes.length) throw invalid();
    if ([192, 193, 194].includes(marker)) {
      const height = bytes.readUInt16BE(at + 3);
      const width = bytes.readUInt16BE(at + 5);
      const components = bytes[at + 7];
      if (!width || !height || width * height > 100_000_000 || ![1, 3].includes(components)) throw invalid();
      return { width, height, components };
    }
    at += length;
  }
  throw invalid();
}

function paethPredictor(a: number, b: number, c: number) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/** Decode 8-bit PNG (Grayscale, RGB, RGBA, Palette) into PDF FlateDecode RGB/Gray stream. */
function decodePngForPdf(bytes: Buffer): { width: number; height: number; colorSpace: 'DeviceGray' | 'DeviceRGB'; compressed: Buffer } {
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) {
    throw invalid();
  }
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let interlace = 0;
  let palette: Buffer | undefined;
  const idat: Buffer[] = [];
  let offset = 8;
  while (offset + 8 <= bytes.length) {
    const len = bytes.readUInt32BE(offset);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    offset += 8;
    if (offset + len + 4 > bytes.length) throw invalid();
    const chunk = bytes.subarray(offset, offset + len);
    offset += len + 4;
    if (type === 'IHDR') {
      width = chunk.readUInt32BE(0);
      height = chunk.readUInt32BE(4);
      bitDepth = chunk[8]!;
      colorType = chunk[9]!;
      interlace = chunk[12]!;
    } else if (type === 'PLTE') {
      palette = chunk;
    } else if (type === 'IDAT') {
      idat.push(chunk);
    } else if (type === 'IEND') {
      break;
    }
  }
  if (!width || !height || width * height > 50_000_000 || bitDepth !== 8 || interlace !== 0) {
    throw invalid();
  }
  const channels = colorType === 0 ? 1 : colorType === 2 ? 3 : colorType === 3 ? 1 : colorType === 4 ? 2 : colorType === 6 ? 4 : 0;
  if (!channels || (colorType === 3 && !palette)) throw invalid();
  const stride = width * channels;
  const raw = inflateSync(Buffer.concat(idat), { maxOutputLength: height * (stride + 1) + 64 });
  if (raw.length < height * (stride + 1)) throw invalid();

  const recon = Buffer.allocUnsafe(height * stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)]!;
    const srcStart = y * (stride + 1) + 1;
    const dstStart = y * stride;
    for (let x = 0; x < stride; x++) {
      const val = raw[srcStart + x]!;
      const left = x >= channels ? recon[dstStart + x - channels]! : 0;
      const up = y > 0 ? recon[dstStart - stride + x]! : 0;
      const upLeft = y > 0 && x >= channels ? recon[dstStart - stride + x - channels]! : 0;
      const out =
        filter === 0
          ? val
          : filter === 1
            ? val + left
            : filter === 2
              ? val + up
              : filter === 3
                ? val + ((left + up) >> 1)
                : val + paethPredictor(left, up, upLeft);
      recon[dstStart + x] = out & 0xff;
    }
  }

  if (colorType === 0) {
    return { width, height, colorSpace: 'DeviceGray', compressed: deflateSync(recon) };
  }
  if (colorType === 2) {
    return { width, height, colorSpace: 'DeviceRGB', compressed: deflateSync(recon) };
  }
  // Composite alpha against white for PDF print/read clarity or expand palette
  const rgb = Buffer.allocUnsafe(width * height * 3);
  const pixelCount = width * height;
  if (colorType === 3 && palette) {
    for (let i = 0; i < pixelCount; i++) {
      const idx = recon[i]! * 3;
      rgb[i * 3] = palette[idx] ?? 0;
      rgb[i * 3 + 1] = palette[idx + 1] ?? 0;
      rgb[i * 3 + 2] = palette[idx + 2] ?? 0;
    }
  } else if (colorType === 4) {
    for (let i = 0; i < pixelCount; i++) {
      const g = recon[i * 2]!;
      const a = recon[i * 2 + 1]!;
      const v = Math.round((g * a + 255 * (255 - a)) / 255);
      rgb[i * 3] = v;
      rgb[i * 3 + 1] = v;
      rgb[i * 3 + 2] = v;
    }
  } else {
    for (let i = 0; i < pixelCount; i++) {
      const r = recon[i * 4]!;
      const g = recon[i * 4 + 1]!;
      const b = recon[i * 4 + 2]!;
      const a = recon[i * 4 + 3]!;
      rgb[i * 3] = Math.round((r * a + 255 * (255 - a)) / 255);
      rgb[i * 3 + 1] = Math.round((g * a + 255 * (255 - a)) / 255);
      rgb[i * 3 + 2] = Math.round((b * a + 255 * (255 - a)) / 255);
    }
  }
  return { width, height, colorSpace: 'DeviceRGB', compressed: deflateSync(rgb) };
}

/** Supports both JPEG (/DCTDecode) and PNG (/FlateDecode) directly on the server. */
export function createComicPdf(images: Buffer[]): Buffer {
  if (!images.length || images.length > 1000 || images.reduce((n, b) => n + b.length, 0) > 256 * 1024 * 1024) {
    throw invalid();
  }
  const objects: Buffer[] = [];
  const put = (value: string | Buffer) => {
    objects.push(Buffer.isBuffer(value) ? value : Buffer.from(value));
    return objects.length;
  };
  put('<< /Type /Catalog /Pages 2 0 R >>');
  put('');
  const pages: number[] = [];
  const pageWidth = 595.28;

  for (const bytes of images) {
    let width: number;
    let height: number;
    let imageObjId: number;
    if (bytes[0] === 255 && bytes[1] === 216) {
      const info = jpegSize(bytes);
      width = info.width;
      height = info.height;
      imageObjId = put(
        Buffer.concat([
          Buffer.from(
            `<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace /${info.components === 1 ? 'DeviceGray' : 'DeviceRGB'} /BitsPerComponent 8 /Filter /DCTDecode /Length ${bytes.length} >>\nstream\n`,
          ),
          bytes,
          Buffer.from('\nendstream'),
        ]),
      );
    } else {
      const png = decodePngForPdf(bytes);
      width = png.width;
      height = png.height;
      imageObjId = put(
        Buffer.concat([
          Buffer.from(
            `<< /Type /XObject /Subtype /Image /Width ${width} /Height ${height} /ColorSpace /${png.colorSpace} /BitsPerComponent 8 /Filter /FlateDecode /Length ${png.compressed.length} >>\nstream\n`,
          ),
          png.compressed,
          Buffer.from('\nendstream'),
        ]),
      );
    }
    const pageHeight = (pageWidth * height) / width;
    const draw = Buffer.from(`q\n${pageWidth} 0 0 ${pageHeight} 0 0 cm\n/Im0 Do\nQ`);
    const content = put(
      Buffer.concat([Buffer.from(`<< /Length ${draw.length} >>\nstream\n`), draw, Buffer.from('\nendstream')]),
    );
    pages.push(
      put(
        `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Resources << /XObject << /Im0 ${imageObjId} 0 R >> >> /Contents ${content} 0 R >>`,
      ),
    );
  }
  objects[1] = Buffer.from(`<< /Type /Pages /Count ${pages.length} /Kids [${pages.map((id) => `${id} 0 R`).join(' ')}] >>`);
  const chunks = [Buffer.from('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n', 'latin1')];
  const offsets = [0];
  let length = chunks[0]!.length;
  objects.forEach((body, index) => {
    offsets.push(length);
    const object = Buffer.concat([Buffer.from(`${index + 1} 0 obj\n`), body, Buffer.from('\nendobj\n')]);
    chunks.push(object);
    length += object.length;
  });
  chunks.push(
    Buffer.from(
      `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n${offsets
        .slice(1)
        .map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`)
        .join('')}trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${length}\n%%EOF\n`,
    ),
  );
  return Buffer.concat(chunks);
}
