zstdgrep(1) -- print lines matching a pattern in zstandard-compressed files
============================================================================

SYNOPSIS
--------

`zstdgrep` [<grep-flags>] [--] <pattern> [<files> ...]


DESCRIPTION
-----------
`zstdgrep` runs `grep`(1) on files, or `stdin` if no files argument is given, after decompressing them with `zstdcat`(1).

The <grep-flags> and <pattern> arguments are passed on to `grep`(1), and follow its syntax.
If patterns are given with `-e` or `-f` flags, `zstdgrep` does not look for a <pattern> argument.

`zstdgrep` does not search directories: `-r`, `-R`, `--include`, `--exclude`, `--exclude-from` and `--exclude-dir` are not supported.

Note that modern `grep` alternatives such as `ripgrep` (`rg`(1)) support `zstd`-compressed files out of the box,
and can prove better alternatives than `zstdgrep` notably for unsupported complex pattern searches.
Note though that such alternatives may also feature some minor command line differences.

EXIT STATUS
-----------
`zstdgrep` returns 0 if a line is selected in at least one input, and 1 if no line is selected.
If an error occurs, for example an input that cannot be decompressed or an invalid pattern, 2 is returned, unless `-q` is used and a line is selected.

SEE ALSO
--------
`zstd`(1)

AUTHORS
-------
Thomas Klausner <wiz@NetBSD.org> wrote the original version.
