# Docstrings

The public API of QuikTest is what it does, and is not ever intended to be stable in
a SemVer sense.  Being application code, it isn't intended to integrate into other
packages, so the entire idea of a "breaking change" is on thin ice.

You are of course welcome to import parts of the code for your own purposes, if you'd
like.  My suggestion would be to add some tests of the expected behavior, so that if
I break it, as I reserve the right to do at any time, you'll know what happened.

Now that we've gotten that out of the way, have some docstrings.

```@autodocs
Modules = [QuikTest]
```
