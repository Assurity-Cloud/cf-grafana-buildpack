#!/usr/bin/env bash

for testfile in test/functions/*.sh; do
  bash "$testfile"
done