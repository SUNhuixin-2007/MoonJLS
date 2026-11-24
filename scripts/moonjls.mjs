#!/usr/bin/env node
// File I/O adapter only. JPEG-LS compression and decompression run in MoonBit.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cli = path.join(root, '_build/js/debug/build/cmd/node/node.js');

function usage() {
  throw new Error('Usage: node scripts/moonjls.mjs encode INPUT OUTPUT [--near 0..255] [--interleave none|line|sample]\n       node scripts/moonjls.mjs decode INPUT OUTPUT [--pam]\n       node scripts/moonjls.mjs inspect INPUT');
}

function options(args) {
  const [operation, input, ...rest] = args;
  if (!['encode', 'decode', 'inspect'].includes(operation) || !input) usage();
  let output;
  if (operation !== 'inspect') {
    output = rest.shift();
    if (!output || output.startsWith('--')) usage();
  }
  const result = { operation, input: path.resolve(input), output: output && path.resolve(output), near: 0, mode: -1, pam: false };
  const seen = new Set();
  while (rest.length) {
    const key = rest.shift();
    if (seen.has(key)) usage();
    seen.add(key);
    if (key === '--pam' && operation === 'decode') { result.pam = true; continue; }
    if (operation !== 'encode' || !['--near', '--interleave'].includes(key) || rest.length === 0) usage();
    const value = rest.shift();
    if (key === '--near') {
      if (!/^\d+$/.test(value) || Number(value) > 255) usage();
      result.near = Number(value);
    } else {
      result.mode = ['none', 'line', 'sample'].indexOf(value);
      if (result.mode < 0) usage();
    }
  }
  return result;
}

function build() {
  // Invoke Moon directly, with no shell interpolation of user-controlled paths.
  const command = process.platform === 'win32' ? 'moon.exe' : 'moon';
  const result = spawnSync(command, ['build', 'cmd/node', '--target', 'js', '--deny-warn'], { cwd: root, encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`MoonBit build failed:\n${result.stderr || result.stdout}`);
}

async function main() {
  const settings = options(process.argv.slice(2));
  if (settings.output && settings.input.toLowerCase() === settings.output.toLowerCase()) {
    throw new Error('Input and output must be different files');
  }
  build();
  const library = await import(pathToFileURL(cli).href);
  let inputFd;
  let outputFd;
  let createdOutput = false;
  let completed = false;
  try {
    inputFd = fs.openSync(settings.input, 'r');
    const initial = fs.fstatSync(inputFd, { bigint: true });
    if (!initial.isFile()) throw new Error('Input must be a regular file');
    if (initial.size > 0xffffffffffffffffn) throw new Error('Input size exceeds UInt64');
    if (settings.operation !== 'inspect') {
      // Exclusive creation: existing files are never overwritten.
      outputFd = fs.openSync(settings.output, 'wx');
      createdOutput = true;
    }
    let reads = 0;
    let largestRead = 0;
    const host = {
      read(offset, length) {
        const position = BigInt(offset);
        if (!Number.isInteger(length) || length < 0 || position < 0n || position + BigInt(length) > initial.size) {
          throw new Error('MoonBit requested an invalid source range');
        }
        const bytes = Buffer.alloc(length);
        let filled = 0;
        while (filled < length) {
          const count = fs.readSync(inputFd, bytes, filled, length - filled, position + BigInt(filled));
          if (count === 0) throw new Error('Input changed or returned a short read');
          filled += count;
        }
        reads += 1;
        largestRead = Math.max(largestRead, length);
        return bytes;
      },
      write(bytes) {
        if (outputFd === undefined) throw new Error('Output was not opened');
        let written = 0;
        while (written < bytes.length) {
          const count = fs.writeSync(outputFd, bytes, written, bytes.length - written);
          if (count === 0) throw new Error('Output returned a short write');
          written += count;
        }
        return written;
      },
    };
    const raw = library.convert_file(host, initial.size.toString(), settings.operation, settings.near, settings.mode, settings.pam);
    const report = JSON.parse(raw);
    if (!report.success) throw new Error(report.error || 'MoonBit file operation failed');
    const final = fs.fstatSync(inputFd, { bigint: true });
    if (initial.size !== final.size || initial.mtimeNs !== final.mtimeNs) {
      throw new Error('Input changed during the operation');
    }
    report.host_reads = reads;
    report.largest_read_bytes = largestRead;
    if (outputFd !== undefined) fs.fsyncSync(outputFd);
    completed = true;
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  } finally {
    if (inputFd !== undefined) fs.closeSync(inputFd);
    if (outputFd !== undefined) fs.closeSync(outputFd);
    // Delete only the new file exclusively created by this invocation.
    if (createdOutput && !completed) fs.unlinkSync(settings.output);
  }
}

main().catch(error => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
