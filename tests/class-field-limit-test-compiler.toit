// Copyright (C) 2020 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import host.pipe
import expect show *

main args:
  toit-run := args[0]
  input := "tests/class_field_limit_input.toit"
  pipes := pipe.fork
      true                // use_path
      pipe.PIPE-INHERITED // stdin
      pipe.PIPE-INHERITED // stdout
      pipe.PIPE-INHERITED // stderr
      toit-run
      [
        toit-run,
        input
      ]
  pid  := pipes[3]
  exit-value := pipe.wait-for pid
  exit-code := pipe.exit-code exit-value

  expect-not-null exit-code
  expect-not-equals 0 exit-code
