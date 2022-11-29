# Copyright 2022 John Soo
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

gitDir:

let
  inherit (builtins)
    attrNames
    concatMap
    elemAt
    filter
    foldl'
    isPath
    isString
    match
    pathExists
    readDir
    readFile
    split
    stringLength
    substring
    tryEval
    ;
in

assert !isPath gitDir -> throw "${gitDir} is not an absolute path";
assert !pathExists gitDir -> throw "${gitDir} does not exist";

rec {
  HEAD =
    let
      matches = match lib.head raw.HEAD;
    in
    if isNull matches
    then throw "Failed parsing ${gitDir}/HEAD, got: ${raw.HEAD}"
    else {
      fold = merge:
        let
          rev = elemAt matches 0;

          ref = elemAt matches 1;

          packed-refs' =
            let
              head = if isNull ref then rev else ref;

              key = if isNull ref then "rev" else "ref";
            in
            if isNull packed-refs
            then null
            else
              concatMap (l: if head == l."${key}" then [ l ] else [ ])
                packed-refs;
        in
        if isString rev
        then
          let
            short-match = r: match lib.ref r;

            packed-refs-short-refs =
              concatMap
                (x:
                  let m = short-match x.ref; in
                  if !isNull m then [ (elemAt m 1) ] else [ ])
                (if isNull packed-refs' then [ ] else packed-refs');

            msg = "rev ${rev} not found in ${gitDir}/FETCH_HEAD or ${gitDir}/packed-refs";

            remotes' =
              if (tryEval raw.refs.remotes).success
              then lib.remotesMatching rev ""
              else [ ];

            fetch-heads =
              concatMap (x: if x.rev == rev then [ x ] else [ ])
                (if isNull FETCH_HEAD then [ ] else FETCH_HEAD);
          in
          merge.rev {
            inherit rev;
            short-refs =
              packed-refs-short-refs
              ++ map (x: x.ref) fetch-heads
              ++ concatMap
                (x:
                  let
                    matches = match "refs/remotes/[^/]+/(.*)" x;
                  in
                  if isNull matches
                  then [ ]
                  else [ (elemAt matches 0) ])
                remotes';

            refs =
              let
                packed =
                  if isNull packed-refs
                  then [ ]
                  else map (x: x.ref) packed-refs';

                remotes =
                  if (tryEval raw.refs.remotes).success
                  then
                    filter (n: raw.refs.remotes."${n}" == "directory")
                      (attrNames raw.refs.remotes)
                  else [ ];

                remotePath = x: remote:
                  if pathExists (gitDir + "/refs/remotes/${remote}/${x.ref}")
                  then [ "refs/remotes/${remote}/${x.ref}" ]
                  else [ ];

                fetched =
                  if isNull FETCH_HEAD
                  then [ ]
                  else
                    concatMap
                      (x:
                        if x.type == "tag"
                        then [ "refs/tags/${x.ref}" ]
                        else concatMap (remotePath x) remotes
                      )
                      fetch-heads;
              in
              remotes' ++ packed ++ fetched;
          }
        else
          let
            short-matches = match lib.ref ref;

            short-ref =
              if isNull short-matches
              then throw "failed parsing ${gitDir}/HEAD, got: ${raw.HEAD}"
              else elemAt short-matches 1;

            raw.refs.heads =
              let
                res = lib.tryReadFile (gitDir + "/${ref}");
              in
              {
                "${short-ref}" = tryEval res;
              };

            refs.heads."${short-ref}" =
              let
                val =
                  if raw.refs.heads."${short-ref}".success
                  then raw.refs.heads."${short-ref}".value
                  else throw "${ref} does not exist";

                matches =
                  match "(${lib.sha})\n" val;
              in
              if !isNull matches
              then elemAt matches 0
              else
                throw "failed parsing ${gitDir}/${ref}, got: ${val}";

            packed-ref =
              let
                msg =
                  "${toString ref}${toString rev} missing from ${gitDir}/packed-refs";
              in
              if isNull packed-refs
              then null
              else foldl' (_: x: x) (throw msg) packed-refs';
          in
          merge.ref {
            inherit ref short-ref;
            rev =
              if raw.refs.heads."${short-ref}".success
              then refs.heads."${short-ref}"

              else if isNull packed-refs
              then throw "${gitDir}/${ref} missing and ${gitDir}/packed-refs does not exist"

              else if (tryEval packed-ref).success
              then packed-ref.rev

              else
                throw
                  "could not find current revision in: ${gitDir}/HEAD, ${gitDir}/${ref}, ${gitDir}/packed-refs";
          };

      rev = HEAD.fold { rev = r: r.rev; ref = r: r.rev; };
    };

  FETCH_HEAD =
    if raw.FETCH_HEAD.success
    then
      concatMap
        (l: if isString l then lib.fetchHeadLineP l else [ ])
        (split "\n" raw.FETCH_HEAD.value)
    else null;

  packed-refs =
    if raw.packed-refs.success
    then
      concatMap
        (l: if isString l then lib.refLineP l else [ ])
        (split "\n" raw.packed-refs.value)
    else null;

  raw = {
    HEAD = readFile (gitDir + "/HEAD");

    FETCH_HEAD = tryEval (lib.tryReadFile (gitDir + "/FETCH_HEAD"));

    packed-refs = tryEval (lib.tryReadFile (gitDir + "/packed-refs"));

    refs.remotes = lib.tryReadDir (gitDir + "/refs/remotes");
  };

  lib = {
    # Do not propagate the builtin errors, since they cannot be
    # caught with tryEval, which we want to handle by checking
    # packed-refs as fallback
    tryReadFile = file:
      assert !isPath file -> throw "${file} is not an absolute path";
      if pathExists file
      then readFile file
      else throw "${toString file} does not exist";

    # Do not propagate the builtin errors, since they cannot be
    # caught with tryEval, which we want to handle by checking
    # packed-refs as fallback
    tryReadDir = dir:
      assert !isPath dir -> throw "${dir} is not an absolute path";
      if pathExists dir
      then readDir dir
      else throw "${toString dir} does not exist";

    hexDig = "[a-fA-F0-9]";

    sha = "${lib.hexDig}{40}";

    ref = "refs/(heads|remotes/[^/]+|tags)/(.*)";

    head = "(${lib.sha})\n|ref:[[:space:]]+(.*)\n";

    # a "parser" for a line in ${gitDir}}/packed-refs
    refLineP = l:
      let
        matches = match "(${lib.sha})[[:space:]]+(.*)\n?" l;
      in
      if isNull matches
      then [ ]
      else [{
        rev = elemAt matches 0;
        ref = elemAt matches 1;
      }];

    fetchHeadLineP = l:
      let
        pat = "(${lib.sha})[[:space:]]+(not-for-merge[[:space:]]+)?(branch|tag)[[:space:]]'(.*)'.*";

        matches = match pat l;
      in
      if isNull matches
      then [ ]
      else [{
        rev = elemAt matches 0;
        type = elemAt matches 2;
        ref = elemAt matches 3;
      }];

    remotesMatching = rev: dir:
      let
        d = lib.tryReadDir (gitDir + "/refs/remotes/${dir}");

        d' = attrNames d;

        dirs = filter (p: d."${p}" == "directory") d';

        files = filter (p: d."${p}" == "regular") d';

        refFile = f: gitDir + "/refs/remotes/${dir}/${f}";

        hasRev = f: !isNull (match "${rev}\n" (lib.tryReadFile (refFile f)));

        pref = substring 1 (stringLength dir) dir;
      in
      concatMap (f: if hasRev f then [ "refs/remotes/${pref}/${f}" ] else [ ]) files
      ++ concatMap (p: lib.remotesMatching rev "${dir}/${p}") dirs;

  };
}
