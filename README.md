# nix-git-dir

This library is mostly useful to get current revision information in
a sandbox-friendly manner and as pure nix values.

If you are using flakes this doesn't help you at all. But if you
aren't, then this can help.

* `HEAD.rev` - HEAD revision
* `HEAD.fold` - merge rev or ref information
* `packed-refs` - contents of .git/packed-refs
* `FETCH_HEAD` - contents of .git/FETCH_HEAD

but you may also want to use the file contents in:

* `raw.{HEAD,packed-refs,FETCH_HEAD}`

or the library definitions:

* `lib.hexDig`
* `lib.sha`
* `lib.ref`
* `lib.head`
* `lib.refLineP`
* `lib.tryReadFile`
* `lib.tryReadDir`
* `lib.fetchHeadLineP`
* `lib.remotesMatching`

One very useful reference when working on git dirs:
https://git-scm.com/docs/gitrepository-layout

# Unimplemented (yet)

- submodules

# May never be implemented

- non-file refstore backend
- submodules
