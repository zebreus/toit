// Copyright (C) 2018 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

foo x [] x:
  unresolved

bar x break y:
  unresolved

gee y=3 =:
  unresolved

foobar [:
  unresolved

main:
  foo 3
  bar 1 2 3
