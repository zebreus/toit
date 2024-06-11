// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import io
import zlib show *
import host.pipe
import host.file
import monitor show *

import .io-utils

test-compress str/string expected/ByteArray --uncompressed/bool=false:
  [true, false].do: | gzip |
    [true, false].do: | split-writes |
      do-test 10000 0 str expected uncompressed --gzip=gzip --split-writes=split-writes
      do-test 1 0 str expected uncompressed --gzip=gzip --split-writes=split-writes
      do-test 2 0 str expected uncompressed --gzip=gzip --split-writes=split-writes
      do-test 2 1 str expected uncompressed --gzip=gzip --split-writes=split-writes

do-test chunk-size chunk-offset str/string zlib-expected/ByteArray uncompressed --gzip/bool --split-writes/bool:
  compressor := uncompressed ?
    gzip ? UncompressedGzipEncoder : (UncompressedZlibEncoder --split-writes=split-writes) :
    gzip ? RunLengthGzipEncoder : RunLengthZlibEncoder
  accumulator := io.Buffer
  done := Semaphore
  t := task::
    while ba := compressor.reader.read:
      accumulator.write ba
    done.up
  if chunk-offset != 0:
    compressor.write
      str.copy 0 chunk-offset
  List.chunk-up chunk-offset str.size chunk-size: | from to |
    compressor.write
      str.copy from to
  compressor.close
  compressor.close  // Test it is idempotent.
  e := catch: compressor.write "After close"
  expect e != null
  done.down
  if not gzip:
    // Test output against expected compressed data.
    if not zlib-expected:
      fd := file.Stream.for-write (gzip ? "out.gz" : "out.z")
      fd.out.write accumulator.backing-array 0 accumulator.size
      fd.close
      print accumulator.bytes
      exit 1
    else:
      fail := accumulator.size != zlib-expected.size
      if fail:
        print "Expected $zlib-expected.size, got $accumulator.size"
      zlib-expected.size.repeat: if accumulator.backing-array[it] != zlib-expected[it]: fail = true
      if fail:
        print_ accumulator.bytes.stringify
        fd := file.Stream.for-write "out.z"
        fd.out.write accumulator.backing-array 0 accumulator.size
        fd.close
      expect (not fail)
  else:
    // Test round trip with zcat.
    subprocess := pipe.fork true pipe.PIPE-CREATED pipe.PIPE-CREATED pipe.PIPE-INHERITED "zcat" ["zcat"]
    to-zcat := subprocess[0]  // Stdin of zcat.
    from-zcat := subprocess[1]  // Stdin of zcat.
    pipe.dont-wait-for subprocess[3]  // Avoid zombie processes.
    round-trip := io.Buffer
    task::  // Use a task to avoid deadlock if the pipe fills up.
      to-zcat.write accumulator.backing-array 0 accumulator.size
      to-zcat.close
    while byte-array := from-zcat.read:
      round-trip.write byte-array
    from-zcat.close
    round := round-trip.bytes
    expect round.size == str.size
    str.size.repeat: expect round[it] == (str.at --raw it)

test-io-data:
  input-str := "H" + ("e" * 262) + "llo"
  expected := #[8, 29, 243, 72, 29, 241, 0, 4, 114, 114, 242, 1, 160, 114, 104, 238]
  input := FakeData input-str
  compressor := RunLengthZlibEncoder
  accumulator := io.Buffer
  done := Semaphore
  t := task::
    while ba := compressor.in.read:
      accumulator.write ba
    compressor.in.close
    done.up
  compressor.out.write input
  compressor.out.close
  done.down
  expect-equals expected accumulator.bytes

main:
  test-compress "Hello, World!\n"
    #[0x08, 0x1d, 0x01, 0x0e, 0x00, 0xf1, 0xff, 'H', 'e', 'l', 'l', 'o', ',', ' ', 'W', 'o', 'r', 'l', 'd', '!', '\n', 0x24, 0x12, 0x04, 0x74]
    --uncompressed
  test-compress "Hello, World!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0x2f, 0xca, 0x49, 0x51, 0xe4, 0x02, 0x00, 0x24, 0x12, 0x04, 0x74]
  test-compress "Hello, Woorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xcf, 0x2f, 0xca, 0x49, 0x51, 0xe4, 0x02, 0x00, 0x29, 0xb3, 0x04, 0xe3]
  test-compress "Hello, Wooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xcf, 0xcf, 0x2f, 0xca, 0x49, 0x51, 0xe4, 0x02, 0x00, 0x2f, 0xc3, 0x05, 0x52]
  test-compress "Hello, Woooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0x07, 0x82, 0xa2, 0x9c, 0x14, 0x45, 0x2e, 0x00, 0x36, 0x42, 0x05, 0xc1]
  test-compress "Hello, Wooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0x07, 0x81, 0xa2, 0x9c, 0x14, 0x45, 0x2e, 0x00, 0x3d, 0x30, 0x06, 0x30]
  test-compress
    "Hello, Wooooooooooooooooooooooooooooooooooooooooooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0x27, 0x05, 0x14, 0xe5, 0xa4, 0x28, 0x72, 0x01, 0x00, 0xb6, 0x0a, 0x17, 0x88]
  test-compress
    "Hello, WoOoOoOoOoOoOoOoOoOoOooooooooooooooooooooooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xf7, 0xc7, 0x02, 0x71, 0x81, 0xa2, 0x9c, 0x14, 0x45, 0x2e, 0x00, 0x84, 0x0a, 0x16, 0x48]
  test-compress
    "Hello, WoooooooooooooooooooooooOoOoOoOoOoOoOoOoOooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xc7, 0x0e, 0xfc, 0x31, 0x20, 0x08, 0x14, 0xe5, 0xa4, 0x28, 0x72, 0x01, 0x00, 0xa0, 0xaa, 0x16, 0x68]
  test-compress
    "Hello, WoO.oO.oO.oO.oO.oO.oO.oO.oO.oOooooooooooooooooooooooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xf7, 0xd7, 0xc3, 0x8d, 0xf2, 0x71, 0x81, 0xa2, 0x9c, 0x14, 0x45, 0x2e, 0x00, 0x05, 0x9d, 0x17, 0xe6]
  test-compress
    "Hello, WoO.,oO.,oO.,oO.,oO.,oO.,oO.,oO.oO.oOooooooooooooooooooooooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xf7, 0xd7, 0xd3, 0xc1, 0x83, 0xc1, 0x28, 0x1f, 0x17, 0x28, 0xca, 0x49, 0x51, 0xe4, 0x02, 0x00, 0x6e, 0xf1, 0x19, 0x1a]
  test-compress
    "Hello, WoooooooooooooooooooooooOoOoOoOoOoOoOoOoOooooorld!\n"
    #[0x08, 0x1d, 0xf3, 0x48, 0xcd, 0xc9, 0xc9, 0xd7, 0x51, 0x08, 0xcf, 0xc7, 0x0e, 0xfc, 0x31, 0x20, 0x08, 0x14, 0xe5, 0xa4, 0x28, 0x72, 0x01, 0x00, 0xa0, 0xaa, 0x16, 0x68]
  test-compress
    "Heelllllllooooo,,,,,, Woorrrllllddddd!!!!!!"
    #[8, 29, 243, 72, 77, 205, 129, 128, 124, 16, 208, 1, 3, 133, 240, 252, 252, 162, 162, 162, 28, 32, 72, 1, 1, 69, 48, 0, 0, 84, 105, 14, 79]
  test-compress
    "H" + ("e" * 1000) + "llo"
    #[8, 29, 243, 72, 29, 241, 96, 196, 131, 17, 15, 70, 2, 200, 201, 201, 7, 0, 68, 218, 140, 39]
  // Max count in the deflate format is 258, so we emit some repeats that are
  // on the edge to trigger edge case code.
  test-compress
    "H" + ("e" * 257) + "llo"
    #[8, 29, 243, 72, 29, 233, 32, 39, 39, 31, 0, 152, 24, 102, 245]
  test-compress
    "H" + ("e" * 258) + "llo"
    #[8, 29, 243, 72, 29, 241, 32, 39, 39, 31, 0, 255, 90, 103, 90]
  test-compress
    "H" + ("e" * 259) + "llo"
    #[8, 29, 243, 72, 29, 225, 0, 8, 114, 114, 242, 1, 103, 16, 103, 191]
  test-compress
    "H" + ("e" * 260) + "llo"
    #[8, 29, 243, 72, 29, 233, 0, 8, 114, 114, 242, 1, 207, 28, 104, 36]
  test-compress
    "H" + ("e" * 261) + "llo"
    #[8, 29, 243, 72, 29, 241, 0, 8, 114, 114, 242, 1, 55, 156, 104, 137]
  test-compress
    "H" + ("e" * 262) + "llo"
    #[8, 29, 243, 72, 29, 241, 0, 4, 114, 114, 242, 1, 160, 114, 104, 238]
  lorem-out := io.Buffer
  lorem-out.write LOREM-IPSUM
  lorem-out.write LOREM-IPSUM2
  lorem-out.write LOREM-IPSUM3
  test-compress
    """\
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius,
turpis et commodo pharetra, est eros bibendum elit, nec luctus magna felis
sollicitudin mauris. Integer in mauris eu nibh euismod gravida. Duis ac tellus
et risus vulputate vehicula. Donec lobortis risus a elit. Etiam tempor. Ut
ullamcorper, ligula eu tempor congue, eros est euismod turpis, id tincidunt
sapien risus a quam. Maecenas fermentum consequat mi. Donec fermentum.
Pellentesque malesuada nulla a mi. Duis sapien sem, aliquet nec, commodo eget,
consequat quis, neque. Aliquam faucibus, elit ut dictum aliquet, felis nisl
adipiscing sapien, sed malesuada diam lacus eget erat. Cras mollis scelerisque
nunc. Nullam arcu. Aliquam consequat. Curabitur augue lorem, dapibus quis,
laoreet et, pretium ac, nisi. Aenean magna nisl, mollis quis, molestie eu,
feugiat in, orci. In hac habitasse platea dictumst."""
    lorem-out.bytes

  test-io-data

LOREM-IPSUM ::= #[
    0x08, 0x1d, 0xf3, 0xc9, 0x2f, 0x4a, 0xcd, 0x55, 0xc8, 0x2c, 0x28, 0x2e, 0xcd, 0x55, 0x48, 0xc9,
    0xcf, 0xc9, 0x2f, 0x52, 0x28, 0xce, 0x2c, 0x51, 0x48, 0xcc, 0x4d, 0x2d, 0xd1, 0x51, 0x48, 0xce,
    0xcf, 0x2b, 0x4e, 0x4d, 0x2e, 0x49, 0x2d, 0x29, 0x2d, 0x52, 0x48, 0x4c, 0xc9, 0x2c, 0xc8, 0x2c,
    0x4e, 0xce, 0xcc, 0x4b, 0x57, 0x48, 0xcd, 0xc9, 0x2c, 0xd1, 0x51, 0x28, 0x4e, 0x4d, 0x51, 0x48,
    0xc9, 0x57, 0x48, 0xcd, 0x2c, 0x2d, 0xce, 0xcd, 0x4f, 0x51, 0x28, 0x49, 0xcd, 0x2d, 0xc8, 0x2f,
    0xe2, 0xca, 0xcc, 0x4b, 0xce, 0x4c, 0xc9, 0x4c, 0x29, 0xcd, 0x2b, 0x51, 0x28, 0x2d, 0x51, 0xc8,
    0x49, 0x4c, 0xca, 0x2f, 0x4a, 0x55, 0x48, 0x2d, 0x51, 0x48, 0xc9, 0xcf, 0xc9, 0x2f, 0x4a, 0x55,
    0xc8, 0x4d, 0x4c, 0xcf, 0x4b, 0x54, 0x48, 0xcc, 0xc9, 0x2c, 0x2c, 0x4d, 0xd4, 0x53, 0x08, 0x2d,
    0x51, 0x48, 0xcd, 0xcb, 0xcc, 0x55, 0x48, 0x4c, 0x51, 0xc8, 0xcd, 0xcc, 0xcb, 0xcc, 0x55, 0x28,
    0x4b, 0xcd, 0xcb, 0x4c, 0xcc, 0xd5, 0x51, 0x28, 0x2c, 0xcd, 0x2c, 0xe6, 0xca, 0xcb, 0x2f, 0x2e,
    0x29, 0x2a, 0x4d, 0x51, 0x48, 0xad, 0x48, 0x2d, 0x4a, 0xce, 0x2c, 0x49, 0x2c, 0xc9, 0xcc, 0xcf,
    0x53, 0x28, 0xcd, 0xc9, 0x49, 0xcc, 0x4d, 0xce, 0x57, 0xc8, 0x49, 0x4c, 0xca, 0x2f, 0xca, 0x2c,
    0x56, 0xc8, 0xcb, 0x2c, 0xce, 0x54, 0x28, 0x2d, 0x51, 0x48, 0xcc, 0xc9, 0x2c, 0x2c, 0xcd, 0x2c,
    0x50, 0x48, 0xad, 0x50, 0x48, 0x4d, 0x54, 0x48, 0xce, 0xcf, 0xcd, 0xcd, 0x4f, 0xc9, 0x57, 0x48,
    0xce, 0xcf, 0x2b, 0x4e, 0x2d, 0x2c, 0x4d, 0x2c, 0xd1, 0xe3, 0x72, 0x29, 0xcd, 0x2c, 0x56, 0x48,
    0x2c, 0x2d, 0x49, 0x55, 0xc8, 0x2c, 0x2a, 0x2d, 0x4a, 0x55, 0x48, 0xc9, 0xcf, 0xc9, 0x2f, 0x52,
    0xc8, 0xcc, 0x53, 0x28, 0x4a, 0x2d, 0x28, 0x4a, 0xcd, 0x48, 0xcd, 0x4b, 0x49, 0x2d, 0xca, 0x2c,
    0x51, 0xc8, 0xcc, 0x53, 0x28, 0xcb, 0xcf, 0x29, 0x2d, 0x28, 0x49, 0x2c, 0x49, 0x55, 0x28, 0x4b,
    0xcd, 0xc9, 0x2c, 0x51, 0x48, 0x2d, 0x2e, 0x4e, 0x55, 0x48, 0xce, 0xcc, 0xc9, 0x29, 0xcd, 0x55,
    0x48, 0xc9, 0xcf, 0xc9, 0x2f, 0x4a, 0x55, 0x48, 0x2d, 0xe5, 0x4a, 0x2b, 0x4d, 0xcf, 0x4c, 0x2c,
    0x51, 0xc8, 0x2b, 0xcd, 0xc9, 0x49, 0x54, 0x28, 0x48, 0x2c, 0xca, 0x4c, 0x2c, 0x29, 0x2d, 0xd2,
    0x53, 0x70, 0xad, 0x48, 0x4e, 0x2d, 0x28, 0x49, 0x2d, 0x2d, 0x52, 0x28, 0xce, 0xcc, 0x2b, 0x51,
    0xc8, 0x4f, 0x4e, 0x4e, 0x4c, 0x4d, 0x4e, 0x2c, 0x51, 0x48, 0x2e, 0x2d, 0xc8, 0x4c, 0x49, 0x2c,
    0x49, 0x2c, 0x51, 0xc8, 0xcb, 0xcf, 0x53, 0x28, 0x28, 0xca, 0xcf, 0x4c, 0x49, 0xcd, 0x2b, 0xd1,
    0x51, 0x28, 0x2e, 0xcd, 0x2b, 0x51, 0xc8, 0xcc, 0xe3, 0x4a, 0x2e, 0xcd, 0x29, 0x48, 0x54, 0x28,
    0x2c, 0xcd, 0x54, 0xc8, 0x4f, 0x4b, 0xcb, 0x4c, 0xce, 0x4c, 0x54, 0x48, 0x49, 0x2d, 0x4e, 0x2d,
    0x2a, 0xcd, 0x2b, 0x51, 0xc8, 0xcd, 0xcf, 0xc9, 0xc9, 0x2c, 0x51, 0x48, 0xcc, 0xcb, 0xcc, 0x55,
    0xc8, 0x4c, 0x51, 0x48, 0x2d, 0x2e, 0x51, 0xc8, 0x49, 0x4c, 0xca, 0x2f, 0x2a, 0xcd, 0xd5, 0xe3,
    0xe2, 0x72, 0x2e, 0x2d, 0x4a, 0x4c, 0xca, 0x2c, 0x29, 0x2d, 0x52, 0x28, 0x28, 0x4a, 0x2d, 0xc9,
    0x2c, 0xcd, 0x55, 0x28, 0xc9, 0xcc, 0x4b, 0xce, 0x4c, 0x29, 0xcd, 0x2b, 0x51, 0xc8, 0x49, 0x4c]

LOREM-IPSUM2 ::= #[
    0x2e, 0x2d, 0xd6, 0x53, 0xf0, 0x2b, 0xcd, 0xc9, 0x49, 0x54, 0x48, 0x2f, 0x4a, 0x2c, 0xcb, 0x4c,
    0x49, 0x54, 0xc8, 0x2f, 0x4a, 0xce, 0x54, 0x48, 0x54, 0xc8, 0x4f, 0xc9, 0xcc, 0xd7, 0x53, 0xf0,
    0x2b, 0xcd, 0xc9, 0x49, 0xcc, 0x55, 0x28, 0x4b, 0x2c, 0xca, 0x2c, 0x2d, 0xd6, 0xe1, 0x2a, 0x29,
    0x2d, 0x2a, 0xc8, 0x2c, 0x56, 0x48, 0x2d, 0x51, 0x48, 0xce, 0xcf, 0xcd, 0xcd, 0x4f, 0xc9, 0x57,
    0x28, 0xc8, 0x48, 0x2c, 0x4a, 0x2d, 0x29, 0x4a, 0xd4, 0x51, 0x48, 0x2d, 0x2e, 0x51, 0x48, 0x2d,
    0xca, 0x2f, 0x56, 0x48, 0xca, 0x4c, 0x4a, 0xcd, 0x4b, 0x29, 0xcd, 0x55, 0x48, 0xcd, 0xc9, 0x2c,
    0xd1, 0x51, 0xc8, 0x4b, 0x4d, 0x56, 0xc8, 0x29, 0x4d, 0x2e, 0x29, 0x2d, 0x56, 0xc8, 0x4d, 0x4c,
    0xcf, 0x4b, 0x54, 0x48, 0x4b, 0xcd, 0xc9, 0x2c, 0xe6, 0x2a, 0xce, 0xcf, 0xc9, 0xc9, 0x4c, 0xce,
    0x2c, 0x29, 0x4d, 0xc9, 0xcc, 0x53, 0xc8, 0x4d, 0x2c, 0x2d, 0xca, 0x2c, 0xd6, 0x53, 0xf0, 0xcc,
    0x2b, 0x49, 0x4d, 0x4f, 0x2d, 0x52, 0xc8, 0xcc, 0x53, 0xc8, 0x4d, 0x2c, 0x2d, 0xca, 0x2c, 0x56,
    0x48, 0x2d, 0x55, 0xc8, 0xcb, 0x4c, 0xca, 0x50, 0x48, 0x2d, 0xcd, 0x2c, 0xce, 0xcd, 0x4f, 0x51,
    0x48, 0x2f, 0x4a, 0x2c, 0xcb, 0x4c, 0x49, 0xd4, 0x53, 0x70, 0x29, 0xcd, 0x2c, 0x56, 0x48, 0x4c,
    0x56, 0x28, 0x49, 0xcd, 0xc9, 0x29, 0x2d, 0xe6, 0x4a, 0x2d, 0x51, 0x28, 0xca, 0x2c, 0x2e, 0x2d,
    0x56, 0x28, 0x2b, 0xcd, 0x29, 0x28, 0x2d, 0x49, 0x2c, 0x49, 0x55, 0x28, 0x4b, 0xcd, 0xc8, 0x4c,
    0x2e, 0xcd, 0x49, 0xd4, 0x53, 0x70, 0xc9, 0xcf, 0x4b, 0x4d, 0x56, 0xc8, 0xc9, 0x4f, 0xca, 0x2f,
    0x2a, 0xc9, 0x2c, 0x56, 0x28, 0xca, 0x2c, 0x2e, 0x2d, 0x56, 0x48, 0x54, 0x48, 0xcd, 0xc9, 0x2c,
    0xd1, 0x53, 0x70, 0x2d, 0xc9, 0x4c, 0xcc, 0x55, 0x28, 0x49, 0xcd, 0x2d, 0xc8, 0x2f, 0xd2, 0x53,
    0x08, 0x2d, 0xe1, 0x2a, 0xcd, 0xc9, 0x49, 0xcc, 0x4d, 0xce, 0x2f, 0x2a, 0x48, 0x2d, 0xd2, 0x51,
    0xc8, 0xc9, 0x4c, 0x2f, 0xcd, 0x49, 0x54, 0x48, 0x2d, 0x55, 0x28, 0x49, 0xcd, 0x2d, 0xc8, 0x2f,
    0x52, 0x48, 0xce, 0xcf, 0x4b, 0x2f, 0x4d, 0xd5, 0x51, 0x48, 0x2d, 0xca, 0x2f, 0x56, 0x48, 0x2d,
    0x2e, 0x51, 0x48, 0x2d, 0xcd, 0x2c, 0xce, 0xcd, 0x4f, 0x51, 0x28, 0x29, 0x2d, 0x2a, 0xc8, 0x2c,
    0xd6, 0x51, 0xc8, 0x4c, 0x51, 0x28, 0xc9, 0xcc, 0x4b, 0xce, 0x4c, 0x29, 0xcd, 0x2b, 0xe1, 0x2a,
    0x4e, 0x2c, 0xc8, 0x4c, 0xcd, 0x53, 0x28, 0xca, 0x2c, 0x2e, 0x2d, 0x56, 0x48, 0x54, 0x28, 0x2c,
    0x4d, 0xcc, 0xd5, 0x53, 0xf0, 0x4d, 0x4c, 0x4d, 0x4e, 0xcd, 0x4b, 0x2c, 0x56, 0x48, 0x4b, 0x2d,
    0xca, 0x4d, 0xcd, 0x2b, 0x29, 0xcd, 0x55, 0x48, 0xce, 0xcf, 0x2b, 0x4e, 0x2d, 0x2c, 0x4d, 0x2c,
    0x51, 0xc8, 0xcd, 0xd4, 0x53, 0x70, 0xc9, 0xcf, 0x4b, 0x4d, 0x56, 0x48, 0x4b, 0x2d, 0xca, 0x4d,
    0xcd, 0x2b, 0x29, 0xcd, 0xd5, 0xe3, 0x0a, 0x48, 0xcd, 0xc9, 0x49, 0xcd, 0x2b, 0x49, 0x2d, 0x2e]

LOREM-IPSUM3 ::= #[
    0x2c, 0x4d, 0x55, 0xc8, 0x4d, 0xcc, 0x49, 0x2d, 0x2e, 0x4d, 0x4c, 0x49, 0x54, 0xc8, 0x2b, 0xcd,
    0xc9, 0x49, 0x54, 0x48, 0x54, 0xc8, 0xcd, 0xd4, 0x53, 0x70, 0x29, 0xcd, 0x2c, 0x56, 0x28, 0x4e,
    0x2c, 0xc8, 0x4c, 0xcd, 0x53, 0x28, 0x4e, 0xcd, 0xd5, 0x51, 0x48, 0xcc, 0xc9, 0x2c, 0x2c, 0x4d,
    0x2d, 0x51, 0xc8, 0x4b, 0x4d, 0xd6, 0x51, 0x48, 0xce, 0xcf, 0xcd, 0xcd, 0x4f, 0xc9, 0x57, 0x48,
    0x4d, 0x4f, 0x2d, 0xd1, 0xe1, 0x4a, 0xce, 0xcf, 0x2b, 0x4e, 0x2d, 0x2c, 0x4d, 0x2c, 0x51, 0x28,
    0x2c, 0xcd, 0x2c, 0xd6, 0x51, 0xc8, 0x4b, 0x2d, 0x2c, 0x4d, 0xd5, 0x53, 0x70, 0xcc, 0xc9, 0x2c,
    0x2c, 0x4d, 0xcc, 0x55, 0x48, 0x4b, 0x2c, 0x4d, 0xce, 0x4c, 0x2a, 0x2d, 0xd6, 0x51, 0x48, 0xcd,
    0xc9, 0x2c, 0x51, 0x28, 0x2d, 0x51, 0x48, 0xc9, 0x4c, 0x2e, 0x29, 0xcd, 0x55, 0x48, 0xcc, 0xc9,
    0x2c, 0x2c, 0x4d, 0x2d, 0xd1, 0x51, 0x48, 0x4b, 0xcd, 0xc9, 0x2c, 0x56, 0xc8, 0xcb, 0x2c, 0xce,
    0xe1, 0x4a, 0x4c, 0xc9, 0x2c, 0xc8, 0x2c, 0x4e, 0xce, 0xcc, 0x4b, 0x57, 0x28, 0x4e, 0x2c, 0xc8,
    0x4c, 0xcd, 0xd3, 0x51, 0x28, 0x4e, 0x4d, 0x51, 0xc8, 0x4d, 0xcc, 0x49, 0x2d, 0x2e, 0x4d, 0x4c,
    0x49, 0x54, 0x48, 0xc9, 0x4c, 0xcc, 0x55, 0xc8, 0x49, 0x4c, 0x2e, 0x2d, 0x56, 0x48, 0x4d, 0x4f,
    0x2d, 0x51, 0x48, 0x2d, 0x4a, 0x2c, 0xd1, 0x53, 0x70, 0x2e, 0x4a, 0x2c, 0x56, 0xc8, 0xcd, 0xcf,
    0xc9, 0xc9, 0x2c, 0x56, 0x28, 0x4e, 0x4e, 0xcd, 0x49, 0x2d, 0xca, 0x2c, 0x2e, 0x2c, 0x4d, 0xe5,
    0xca, 0x2b, 0xcd, 0x4b, 0xd6, 0x53, 0xf0, 0x2b, 0xcd, 0xc9, 0x49, 0xcc, 0x55, 0x48, 0x2c, 0x4a,
    0x2e, 0xd5, 0x53, 0x70, 0xcc, 0xc9, 0x2c, 0x2c, 0x4d, 0xcc, 0x55, 0x48, 0xce, 0xcf, 0x2b, 0x4e,
    0x2d, 0x2c, 0x4d, 0x2c, 0xd1, 0x53, 0x70, 0x2e, 0x2d, 0x4a, 0x4c, 0xca, 0x2c, 0x29, 0x2d, 0x52,
    0x48, 0x2c, 0x4d, 0x2f, 0x4d, 0x55, 0xc8, 0xc9, 0x2f, 0x4a, 0xcd, 0xd5, 0x51, 0x48, 0x49, 0x2c,
    0xc8, 0x4c, 0x2a, 0x2d, 0x56, 0x28, 0x2c, 0xcd, 0x2c, 0xd6, 0xe1, 0xca, 0x49, 0xcc, 0x2f, 0x4a,
    0x4d, 0x2d, 0x51, 0x48, 0x2d, 0xd1, 0x51, 0x28, 0x28, 0x4a, 0x2d, 0xc9, 0x2c, 0xcd, 0x55, 0x48,
    0x4c, 0xd6, 0x51, 0xc8, 0xcb, 0x2c, 0xce, 0xd4, 0x53, 0x70, 0x4c, 0xcd, 0x4b, 0x4d, 0xcc, 0x53,
    0xc8, 0x4d, 0x4c, 0xcf, 0x4b, 0x54, 0xc8, 0xcb, 0x2c, 0xce, 0xd1, 0x51, 0xc8, 0xcd, 0xcf, 0xc9,
    0xc9, 0x2c, 0x56, 0x28, 0x2c, 0xcd, 0x2c, 0xd6, 0x51, 0xc8, 0xcd, 0xcf, 0x49, 0x2d, 0x2e, 0xc9,
    0x4c, 0x55, 0x48, 0x2d, 0xd5, 0xe1, 0x4a, 0x4b, 0x2d, 0x4d, 0xcf, 0x4c, 0x2c, 0x51, 0xc8, 0xcc,
    0xd3, 0x51, 0xc8, 0x2f, 0x4a, 0xce, 0xd4, 0x53, 0xf0, 0xcc, 0x53, 0xc8, 0x48, 0x4c, 0x56, 0xc8,
    0x48, 0x4c, 0xca, 0x2c, 0x49, 0x2c, 0x2e, 0x4e, 0x55, 0x28, 0xc8, 0x49, 0x2c, 0x49, 0x4d, 0x54,
    0x48, 0xc9, 0x4c, 0x2e, 0x29, 0xcd, 0x2d, 0x2e, 0xd1, 0x03, 0x00, 0x37, 0x1b, 0xe6, 0x87]
