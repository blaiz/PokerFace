#! /usr/bin/env node

'use strict';

pokerfaceServer = require "./pokerface-server"

userArgs = process.argv
searchParam = userArgs[2]

if userArgs.indexOf("-h") isnt -1 or userArgs.indexOf("--help") isnt -1 or searchParam is `undefined`
  console.log("cli help")

if userArgs.indexOf("-v") isnt -1 or userArgs.indexOf("--version") isnt -1
  console.log require("./../../package").version
