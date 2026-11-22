// Pure ArkTS RFC 9106 Argon2id v1.3 & Blake2b implementation (zero @kit imports for unit test compatibility).

const BLAKE2B_IV = new Uint32Array([
  0xf3bcc908, 0x6a09e667,
  0x84caa73b, 0xbb67ae85,
  0xfe94f82b, 0x3c6ef372,
  0x5f1d36f1, 0xa54ff53a,
  0xade682d1, 0x510e527f,
  0x2b3e6c1f, 0x9b05688c,
  0xfb41bd6b, 0x1f83d9ab,
  0x137e2179, 0x5be0cd19
]);

const BLAKE2B_SIGMA: number[][] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
];

function addTo64(arr: Uint32Array, aOff: number, bLo: number, bHi: number): void {
  const sumLo = (arr[aOff] >>> 0) + (bLo >>> 0);
  const carry = sumLo >= 0x100000000 ? 1 : 0;
  arr[aOff] = sumLo >>> 0;
  arr[aOff + 1] = ((arr[aOff + 1] >>> 0) + (bHi >>> 0) + carry) >>> 0;
}

function xorRotr64(arr: Uint32Array, dOff: number, sOff: number, rot: number): void {
  const lo = (arr[dOff] ^ arr[sOff]) >>> 0;
  const hi = (arr[dOff + 1] ^ arr[sOff + 1]) >>> 0;
  if (rot === 32) {
    arr[dOff] = hi;
    arr[dOff + 1] = lo;
  } else if (rot === 24) {
    arr[dOff] = ((lo >>> 24) | (hi << 8)) >>> 0;
    arr[dOff + 1] = ((hi >>> 24) | (lo << 8)) >>> 0;
  } else if (rot === 16) {
    arr[dOff] = ((lo >>> 16) | (hi << 16)) >>> 0;
    arr[dOff + 1] = ((hi >>> 16) | (lo << 16)) >>> 0;
  } else {
    // rot === 63 (equivalent to rotl64 by 1)
    arr[dOff] = ((lo << 1) | (hi >>> 31)) >>> 0;
    arr[dOff + 1] = ((hi << 1) | (lo >>> 31)) >>> 0;
  }
}

function blakeG(v: Uint32Array, m: Uint32Array, a: number, b: number, c: number, d: number, xi: number, yi: number): void {
  const a2 = a * 2;
  const b2 = b * 2;
  const c2 = c * 2;
  const d2 = d * 2;
  addTo64(v, a2, v[b2], v[b2 + 1]);
  addTo64(v, a2, m[xi * 2], m[xi * 2 + 1]);
  xorRotr64(v, d2, a2, 32);

  addTo64(v, c2, v[d2], v[d2 + 1]);
  xorRotr64(v, b2, c2, 24);

  addTo64(v, a2, v[b2], v[b2 + 1]);
  addTo64(v, a2, m[yi * 2], m[yi * 2 + 1]);
  xorRotr64(v, d2, a2, 16);

  addTo64(v, c2, v[d2], v[d2 + 1]);
  xorRotr64(v, b2, c2, 63);
}

function blakeCompress(h: Uint32Array, block: Uint8Array, tLo: number, tHi: number, isLast: boolean): void {
  const m = new Uint32Array(32);
  for (let i = 0; i < 32; i++) {
    const o = i * 4;
    m[i] = (block[o] | (block[o + 1] << 8) | (block[o + 2] << 16) | (block[o + 3] << 24)) >>> 0;
  }
  const v = new Uint32Array(32);
  for (let i = 0; i < 16; i++) {
    v[i] = h[i];
    v[16 + i] = BLAKE2B_IV[i];
  }
  v[24] = (v[24] ^ tLo) >>> 0;
  v[25] = (v[25] ^ tHi) >>> 0;
  if (isLast) {
    v[28] = (~v[28]) >>> 0;
    v[29] = (~v[29]) >>> 0;
  }
  for (let r = 0; r < 12; r++) {
    const s = BLAKE2B_SIGMA[r % 10];
    blakeG(v, m, 0, 4, 8, 12, s[0], s[1]);
    blakeG(v, m, 1, 5, 9, 13, s[2], s[3]);
    blakeG(v, m, 2, 6, 10, 14, s[4], s[5]);
    blakeG(v, m, 3, 7, 11, 15, s[6], s[7]);
    blakeG(v, m, 0, 5, 10, 15, s[8], s[9]);
    blakeG(v, m, 1, 6, 11, 12, s[10], s[11]);
    blakeG(v, m, 2, 7, 8, 13, s[12], s[13]);
    blakeG(v, m, 3, 4, 9, 14, s[14], s[15]);
  }
  for (let i = 0; i < 16; i++) {
    h[i] = (h[i] ^ v[i] ^ v[16 + i]) >>> 0;
  }
}

export function blake2b(input: Uint8Array, outLen: number): Uint8Array {
  if (outLen < 1 || outLen > 64) {
    throw new Error('Blake2b output length must be 1..64');
  }
  const h = new Uint32Array(BLAKE2B_IV);
  h[0] = (h[0] ^ (0x01010000 | (outLen & 0xff))) >>> 0;
  const len = input.length;
  const block = new Uint8Array(128);
  let pos = 0;
  while (len - pos > 128) {
    block.set(input.subarray(pos, pos + 128), 0);
    pos += 128;
    const tLo = pos >>> 0;
    const tHi = Math.floor(pos / 0x100000000) >>> 0;
    blakeCompress(h, block, tLo, tHi, false);
  }
  block.fill(0);
  if (pos < len) {
    block.set(input.subarray(pos, len), 0);
  }
  const lastLo = len >>> 0;
  const lastHi = Math.floor(len / 0x100000000) >>> 0;
  blakeCompress(h, block, lastLo, lastHi, true);

  const out = new Uint8Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const word = h[i >> 2];
    out[i] = (word >>> ((i & 3) * 8)) & 0xff;
  }
  return out;
}

function writeLe32(dst: Uint8Array, offset: number, val: number): void {
  const v = val >>> 0;
  dst[offset] = v & 0xff;
  dst[offset + 1] = (v >>> 8) & 0xff;
  dst[offset + 2] = (v >>> 16) & 0xff;
  dst[offset + 3] = (v >>> 24) & 0xff;
}

function hashPrime(tau: number, input: Uint8Array): Uint8Array {
  const seeded = new Uint8Array(4 + input.length);
  writeLe32(seeded, 0, tau);
  seeded.set(input, 4);
  if (tau <= 64) {
    return blake2b(seeded, tau);
  }
  const out = new Uint8Array(tau);
  const r = Math.ceil(tau / 32) - 2;
  let v = blake2b(seeded, 64);
  out.set(v.subarray(0, 32), 0);
  let pos = 32;
  for (let i = 2; i <= r; i++) {
    v = blake2b(v, 64);
    out.set(v.subarray(0, 32), pos);
    pos += 32;
  }
  const rem = tau - 32 * r;
  const last = blake2b(v, rem);
  out.set(last, pos);
  return out;
}

function emitPermuteQuad(out: Uint16Array, pos: number, a: number, b: number, c: number, d: number): number {
  out[pos] = a * 2;
  out[pos + 1] = b * 2;
  out[pos + 2] = c * 2;
  out[pos + 3] = d * 2;
  return pos + 4;
}

function emitPermute16Quads(
  out: Uint16Array, pos: number,
  i0: number, i1: number, i2: number, i3: number,
  i4: number, i5: number, i6: number, i7: number,
  i8: number, i9: number, i10: number, i11: number,
  i12: number, i13: number, i14: number, i15: number
): number {
  let p = emitPermuteQuad(out, pos, i0, i4, i8, i12);
  p = emitPermuteQuad(out, p, i1, i5, i9, i13);
  p = emitPermuteQuad(out, p, i2, i6, i10, i14);
  p = emitPermuteQuad(out, p, i3, i7, i11, i15);
  p = emitPermuteQuad(out, p, i0, i5, i10, i15);
  p = emitPermuteQuad(out, p, i1, i6, i11, i12);
  p = emitPermuteQuad(out, p, i2, i7, i8, i13);
  p = emitPermuteQuad(out, p, i3, i4, i9, i14);
  return p;
}

function buildPermuteQuads(): Uint16Array {
  const quads = new Uint16Array(512);
  let pos = 0;
  // Row pass: 8 rows of 16 uint64s each
  for (let i = 0; i < 8; i++) {
    const b = i * 16;
    pos = emitPermute16Quads(
      quads, pos,
      b, b + 1, b + 2, b + 3,
      b + 4, b + 5, b + 6, b + 7,
      b + 8, b + 9, b + 10, b + 11,
      b + 12, b + 13, b + 14, b + 15
    );
  }
  // Column pass: 8 columns across the 8 rows
  for (let i = 0; i < 8; i++) {
    const b = i * 2;
    pos = emitPermute16Quads(
      quads, pos,
      b, b + 1, b + 16, b + 17,
      b + 32, b + 33, b + 48, b + 49,
      b + 64, b + 65, b + 80, b + 81,
      b + 96, b + 97, b + 112, b + 113
    );
  }
  return quads;
}

const PERMUTE_QUADS: Uint16Array = buildPermuteQuads();

function fillBlockWords(
  prevArr: Uint32Array, prevBase: number,
  refArr: Uint32Array, refBase: number,
  dstArr: Uint32Array, dstBase: number,
  withXor: boolean,
  R: Uint32Array,
  Z: Uint32Array
): void {
  for (let i = 0; i < 256; i++) {
    const val = (prevArr[prevBase + i] ^ refArr[refBase + i]) >>> 0;
    R[i] = val;
    Z[i] = val;
  }

  for (let q = 0; q < 512; q += 4) {
    const a2 = PERMUTE_QUADS[q];
    const b2 = PERMUTE_QUADS[q + 1];
    const c2 = PERMUTE_QUADS[q + 2];
    const d2 = PERMUTE_QUADS[q + 3];

    let aLo = Z[a2];
    let aHi = Z[a2 + 1];
    let bLo = Z[b2];
    let bHi = Z[b2 + 1];
    let cLo = Z[c2];
    let cHi = Z[c2 + 1];
    let dLo = Z[d2];
    let dHi = Z[d2 + 1];

    // Step 1: fBlaMka(a, b); xorRotr64(d, a, 32)
    let x0 = aLo & 0xffff;
    let x1 = aLo >>> 16;
    let y0 = bLo & 0xffff;
    let y1 = bLo >>> 16;
    let p00 = x0 * y0;
    let p01 = x0 * y1;
    let p10 = x1 * y0;
    let mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
    let prodLo = ((p00 & 0xffff) | ((mid & 0xffff) << 16)) >>> 0;
    let prodHi = ((mid >>> 16) + (p01 >>> 16) + (p10 >>> 16) + x1 * y1) >>> 0;
    let sumLo = aLo + bLo + ((prodLo << 1) >>> 0);
    aLo = sumLo >>> 0;
    aHi = (aHi + bHi + (((prodHi << 1) | (prodLo >>> 31)) >>> 0) + ((sumLo / 4294967296) | 0)) >>> 0;

    let tLo = (dLo ^ aLo) >>> 0;
    let tHi = (dHi ^ aHi) >>> 0;
    dLo = tHi;
    dHi = tLo;

    // Step 2: fBlaMka(c, d); xorRotr64(b, c, 24)
    x0 = cLo & 0xffff;
    x1 = cLo >>> 16;
    y0 = dLo & 0xffff;
    y1 = dLo >>> 16;
    p00 = x0 * y0;
    p01 = x0 * y1;
    p10 = x1 * y0;
    mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
    prodLo = ((p00 & 0xffff) | ((mid & 0xffff) << 16)) >>> 0;
    prodHi = ((mid >>> 16) + (p01 >>> 16) + (p10 >>> 16) + x1 * y1) >>> 0;
    sumLo = cLo + dLo + ((prodLo << 1) >>> 0);
    cLo = sumLo >>> 0;
    cHi = (cHi + dHi + (((prodHi << 1) | (prodLo >>> 31)) >>> 0) + ((sumLo / 4294967296) | 0)) >>> 0;

    tLo = (bLo ^ cLo) >>> 0;
    tHi = (bHi ^ cHi) >>> 0;
    bLo = ((tLo >>> 24) | (tHi << 8)) >>> 0;
    bHi = ((tHi >>> 24) | (tLo << 8)) >>> 0;

    // Step 3: fBlaMka(a, b); xorRotr64(d, a, 16)
    x0 = aLo & 0xffff;
    x1 = aLo >>> 16;
    y0 = bLo & 0xffff;
    y1 = bLo >>> 16;
    p00 = x0 * y0;
    p01 = x0 * y1;
    p10 = x1 * y0;
    mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
    prodLo = ((p00 & 0xffff) | ((mid & 0xffff) << 16)) >>> 0;
    prodHi = ((mid >>> 16) + (p01 >>> 16) + (p10 >>> 16) + x1 * y1) >>> 0;
    sumLo = aLo + bLo + ((prodLo << 1) >>> 0);
    aLo = sumLo >>> 0;
    aHi = (aHi + bHi + (((prodHi << 1) | (prodLo >>> 31)) >>> 0) + ((sumLo / 4294967296) | 0)) >>> 0;

    tLo = (dLo ^ aLo) >>> 0;
    tHi = (dHi ^ aHi) >>> 0;
    dLo = ((tLo >>> 16) | (tHi << 16)) >>> 0;
    dHi = ((tHi >>> 16) | (tLo << 16)) >>> 0;

    // Step 4: fBlaMka(c, d); xorRotr64(b, c, 63)
    x0 = cLo & 0xffff;
    x1 = cLo >>> 16;
    y0 = dLo & 0xffff;
    y1 = dLo >>> 16;
    p00 = x0 * y0;
    p01 = x0 * y1;
    p10 = x1 * y0;
    mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
    prodLo = ((p00 & 0xffff) | ((mid & 0xffff) << 16)) >>> 0;
    prodHi = ((mid >>> 16) + (p01 >>> 16) + (p10 >>> 16) + x1 * y1) >>> 0;
    sumLo = cLo + dLo + ((prodLo << 1) >>> 0);
    cLo = sumLo >>> 0;
    cHi = (cHi + dHi + (((prodHi << 1) | (prodLo >>> 31)) >>> 0) + ((sumLo / 4294967296) | 0)) >>> 0;

    tLo = (bLo ^ cLo) >>> 0;
    tHi = (bHi ^ cHi) >>> 0;
    bLo = ((tLo << 1) | (tHi >>> 31)) >>> 0;
    bHi = ((tHi << 1) | (tLo >>> 31)) >>> 0;

    Z[a2] = aLo;
    Z[a2 + 1] = aHi;
    Z[b2] = bLo;
    Z[b2 + 1] = bHi;
    Z[c2] = cLo;
    Z[c2 + 1] = cHi;
    Z[d2] = dLo;
    Z[d2 + 1] = dHi;
  }

  if (withXor) {
    for (let i = 0; i < 256; i++) {
      dstArr[dstBase + i] = (dstArr[dstBase + i] ^ R[i] ^ Z[i]) >>> 0;
    }
  } else {
    for (let i = 0; i < 256; i++) {
      dstArr[dstBase + i] = (R[i] ^ Z[i]) >>> 0;
    }
  }
}

// Compute floor((a * b) / 2^32) for unsigned 32-bit integers without floating-point precision loss
function mulHi32(a: number, b: number): number {
  const ua = a >>> 0;
  const ub = b >>> 0;
  const a0 = ua & 0xffff;
  const a1 = ua >>> 16;
  const b0 = ub & 0xffff;
  const b1 = ub >>> 16;
  const p00 = a0 * b0;
  const p01 = a0 * b1;
  const p10 = a1 * b0;
  const p11 = a1 * b1;
  const mid = (p00 >>> 16) + (p01 & 0xffff) + (p10 & 0xffff);
  return ((mid >>> 16) + (p01 >>> 16) + (p10 >>> 16) + p11) >>> 0;
}

function indexAlpha(
  pass: number,
  slice: number,
  index: number,
  segmentLen: number,
  laneLen: number,
  sameLane: boolean,
  j1: number
): number {
  let refAreaSize = 0;
  if (pass === 0) {
    if (slice === 0) {
      refAreaSize = index - 1;
    } else if (sameLane) {
      refAreaSize = slice * segmentLen + index - 1;
    } else {
      refAreaSize = slice * segmentLen + (index === 0 ? -1 : 0);
    }
  } else {
    if (sameLane) {
      refAreaSize = laneLen - segmentLen + index - 1;
    } else {
      refAreaSize = laneLen - segmentLen + (index === 0 ? -1 : 0);
    }
  }
  const j1u = j1 >>> 0;
  const x = mulHi32(j1u, j1u);
  const y = mulHi32(refAreaSize >>> 0, x);
  const relPos = refAreaSize - 1 - y;
  const startPos = (pass !== 0 && slice !== 3) ? (slice + 1) * segmentLen : 0;
  return (startPos + relPos) % laneLen;
}

export function argon2id(
  password: Uint8Array,
  salt: Uint8Array,
  memoryKiB: number,
  passes: number,
  lanes: number,
  tagLen: number
): Uint8Array {
  if (passes < 1 || lanes < 1 || tagLen < 4) {
    throw new Error('Invalid Argon2id parameters');
  }
  const minMem = 8 * lanes;
  let blockCount = Math.max(minMem, memoryKiB);
  const segmentLen = Math.floor(blockCount / (4 * lanes));
  const laneLen = segmentLen * 4;
  blockCount = laneLen * lanes;

  // Build H0
  const h0Input = new Uint8Array(40 + password.length + salt.length);
  writeLe32(h0Input, 0, lanes);
  writeLe32(h0Input, 4, tagLen);
  writeLe32(h0Input, 8, memoryKiB);
  writeLe32(h0Input, 12, passes);
  writeLe32(h0Input, 16, 0x13); // v1.3
  writeLe32(h0Input, 20, 2);    // Argon2id
  writeLe32(h0Input, 24, password.length);
  h0Input.set(password, 28);
  const sOff = 28 + password.length;
  writeLe32(h0Input, sOff, salt.length);
  h0Input.set(salt, sOff + 4);
  writeLe32(h0Input, sOff + 4 + salt.length, 0);
  writeLe32(h0Input, sOff + 8 + salt.length, 0);
  const h0 = blake2b(h0Input, 64);

  const mem = new Uint32Array(blockCount * 256);
  const seed = new Uint8Array(72);
  seed.set(h0, 0);

  for (let lane = 0; lane < lanes; lane++) {
    writeLe32(seed, 68, lane);
    for (let idx = 0; idx < 2; idx++) {
      writeLe32(seed, 64, idx);
      const blk = hashPrime(1024, seed);
      const wordBase = (lane * laneLen + idx) * 256;
      for (let w = 0; w < 256; w++) {
        const o = w * 4;
        mem[wordBase + w] = (blk[o] | (blk[o + 1] << 8) | (blk[o + 2] << 16) | (blk[o + 3] << 24)) >>> 0;
      }
    }
  }

  const R = new Uint32Array(256);
  const Z = new Uint32Array(256);
  const zeroBlock = new Uint32Array(256);
  const inputBlock = new Uint32Array(256);
  const addrBlock = new Uint32Array(256);
  const tmpBlock = new Uint32Array(256);

  for (let pass = 0; pass < passes; pass++) {
    for (let slice = 0; slice < 4; slice++) {
      for (let lane = 0; lane < lanes; lane++) {
        const dataIndependent = pass === 0 && slice < 2;
        let counter = 0;
        let lastChunk = -1;
        if (dataIndependent) {
          inputBlock.fill(0);
          inputBlock[0] = pass >>> 0;
          inputBlock[2] = lane >>> 0;
          inputBlock[4] = slice >>> 0;
          inputBlock[6] = blockCount >>> 0;
          inputBlock[8] = passes >>> 0;
          inputBlock[10] = 2; // Argon2id
        }

        const startIdx = (pass === 0 && slice === 0) ? 2 : 0;
        let currOffset = slice * segmentLen + startIdx;
        let prevOffset = currOffset === 0 ? laneLen - 1 : currOffset - 1;
        const laneWordOffset = lane * laneLen;

        for (let idx = startIdx; idx < segmentLen; idx++, currOffset++, prevOffset++) {
          if (currOffset % laneLen === 1) {
            prevOffset = currOffset - 1;
          }
          let j1 = 0;
          let j2 = 0;
          if (dataIndependent) {
            const chunk = Math.floor(idx / 128);
            if (chunk !== lastChunk) {
              counter++;
              inputBlock[12] = counter >>> 0;
              fillBlockWords(zeroBlock, 0, inputBlock, 0, tmpBlock, 0, false, R, Z);
              fillBlockWords(zeroBlock, 0, tmpBlock, 0, addrBlock, 0, false, R, Z);
              lastChunk = chunk;
            }
            const slot = (idx % 128) * 2;
            j1 = addrBlock[slot];
            j2 = addrBlock[slot + 1];
          } else {
            const prevWordBase = (laneWordOffset + prevOffset) * 256;
            j1 = mem[prevWordBase];
            j2 = mem[prevWordBase + 1];
          }

          const refLane = (pass === 0 && slice === 0) ? lane : ((j2 >>> 0) % lanes);
          const sameLane = refLane === lane;
          const refIndex = indexAlpha(pass, slice, idx, segmentLen, laneLen, sameLane, j1);
          const refWordBase = (refLane * laneLen + refIndex) * 256;
          const prevWordBase = (laneWordOffset + prevOffset) * 256;
          const currWordBase = (laneWordOffset + currOffset) * 256;

          fillBlockWords(
            mem, prevWordBase,
            mem, refWordBase,
            mem, currWordBase,
            pass > 0,
            R, Z
          );
          if (prevOffset === laneLen - 1) {
            prevOffset = -1;
          }
        }
      }
    }
  }

  const finalWords = new Uint32Array(256);
  const firstLastBase = (laneLen - 1) * 256;
  for (let w = 0; w < 256; w++) {
    finalWords[w] = mem[firstLastBase + w];
  }
  for (let lane = 1; lane < lanes; lane++) {
    const lastBase = (lane * laneLen + laneLen - 1) * 256;
    for (let w = 0; w < 256; w++) {
      finalWords[w] = (finalWords[w] ^ mem[lastBase + w]) >>> 0;
    }
  }

  const finalBytes = new Uint8Array(1024);
  for (let w = 0; w < 256; w++) {
    writeLe32(finalBytes, w * 4, finalWords[w]);
  }
  const tag = hashPrime(tagLen, finalBytes);

  // Best-effort zeroing of sensitive scratch
  h0Input.fill(0);
  seed.fill(0);
  h0.fill(0);
  finalWords.fill(0);
  finalBytes.fill(0);
  R.fill(0);
  Z.fill(0);
  mem.fill(0);
  return tag;
}
