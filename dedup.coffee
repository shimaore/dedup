#!/usr/bin/env coffee

usage = ->
  "Usage: dedup < list-of-files-to-dedup-one-per-line"

fs = require 'fs'
crypto = require 'crypto'
byline = require 'byline'
Q = require 'q'

hash = (filename) ->
  d = Q.defer()
  shasum = crypto.createHash 'sha1'

  s = fs.createReadStream filename
  s.on 'data', (d) ->
    shasum.update d

  s.on 'end', ->
    d.resolve shasum.digest('hex')

  s.on 'error', (e) ->
    d.reject e

  d.promise

hash.test = ->
  found = null
  hash('/dev/null').then( (v) -> found = v ).done()
  setTimeout (-> console.assert found is 'da39a3ee5e6b4b0d3255bfef95601890afd80709'), 200

# do hash.test

queue = {}
concurrent = 0
max_concurrent = 20

@run = ->
  hashes = {}

  remove_dups = ->
    for k,v of hashes
      if v.length > 1
        # Make sure the dedup is stable
        v.sort() # sort in place
        keep = v.shift() # keep the first file
        for n in v
          console.log "Removing #{n}, a duplicate of #{keep}"
          fs.unlinkSync n

  finalize = false

  hash_one = (filename) ->
    d = hash filename

    make_concurrent = (next) ->
      (v) ->
        delete queue[filename]
        concurrent -= 1
        if concurrent < max_concurrent
          # resume
          filenames.resume()
          # /resume

        next? arguments...

        if finalize and concurrent is 0
          do remove_dups

    accepted = make_concurrent (v) ->
      hashes[v] ?= []
      hashes[v].push filename

    rejected = make_concurrent null

    d.then(accepted, rejected).done()

  # Read through the filenames
  filenames = byline process.stdin
  filenames.setEncoding 'utf-8'

  filenames.on 'data', (filename) ->
    # Duplicate entry
    if queue[filename]
      console.error "Duplicate file #{filename}"
      return
    # Restrict number of concurrent open file descriptors.
    concurrent += 1
    queue[filename] = true
    if concurrent >= max_concurrent
      # throttle
      filenames.pause()
      # /throttle

    hash_one filename

  filenames.on 'end', ->
    finalize = true
    # if concurrent is 0
    #  remove_dups
