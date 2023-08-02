#!/usr/bin/env bash

set +e

for testfile in test/functions/*.sh; do
  bash "$testfile"
done