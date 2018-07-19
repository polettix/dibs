[//]: # vim: ts=4 sts=4 sw=4 et ai colorcolumn=79 tw=78 :

# dibs - Docker image build system

`dibs` aims at automating the process from code to Docker image, with
flexibility as to the base images used (mainly to enable building on top
of Alpine Linux).

`dibs` itself is a driver program that does nearly nothing... or better:

- supports a sophisticated way of providing configurations
- iterates over steps defined in the configuration
- automates lookup of code to execute in each step, calling `docker` when
  needed and saving images along the way, when requested to do so
- automates rollback of saved images if something goes wrong

## Basics

`dibs` assumes that there is a *project directory* where things are kept
nicely. The basic structure of a project is the following:

    <PROJECT_DIR>
        - dibs.yml
        - dibspacks
        - cache
        - env
        - src

`dibs` also expects to find a configuration file. By default, it's the
`dibs.txt` file you see in the directory structure above, but you have means
to provide an alternative one. More on how to set the configuration can be
found down in section *Configuration*.

The actual operations are performed through *dibspack*s. The starting idea is
taken from Heroku's buildpacks, but there is actually little resemblance left
as of now. A dibspack is a directory (or something that can eventually be
resolved to be a directory, like a git URI) that contains two executable
programs:

- `detect`: establishes if the buildpack is suitable for running in the
  specific context
- `operate`: contains the actual logic of the dibspack.

The `detect` program is run first: if its exit code is `0` the `operate`
program is called, otherwise the dibspack is skipped.

So, for using `dibs` you have to:

- create a project directory
- code/fetch/find suitable dibspack for your specific needs
- define a configuration file `dibs.yml`
- run `dibs`.

We will see the different steps in the following.


## Project Directory

The project directory is where all fun happens. You don't need anything fancy,
just a directory:

    $ mkdir project
    $ cd project

Unless you are going to use a dibspack to fetch your code automatically (e.g.
from a git remote), you can put your code in the `src` directory:

    $ mkdir src
    $ echo 'this is all my code' > src/da-code.txt

This is actually it. Other *standard* sub-directories (like `cache`, ...)
will be created as needed by `dibs`, unless you create them yourselves.

You can put additional stuff in this directory if you want! E.g. you might
want to source-control it with git, add a `README.md` file with some
documentation, etc.

## Dibspacks

Dibspacks are at the real core of `dibs`; it would be able to do very little
without. We already touched upon what a dibspack is: a directory with two
executable inside (`detect` and `operate`). Well, actually if `detect` always
returns a non-`0` value you can spare the `operate`, but at that point you
would have a pretty lame dibspack.

`dibs` supports different ways for you to configure the location of dibspacks,
which should cover a wide range of needs:

- the most natural place to define a list of dibspacks is in each step's
  configuration in the `dibs.yml` file (or whatever you are going to use)
- as a fallback, they might be defined directly in your code, i.e. inside
  `src/.dibspacks`. There are two sub-alternatives here:
    - if `.dibspacks` is a file, then each line is the location of a
      dibspack
    - if `.dibspacks` is a directory, each sub-directory is a dibspack that
      matches the name of a corresponding step. E.g. if you have a step called
      `build`, the `build` sub-directory will be its (only) dibspack

Locations can have different shapes:

- anything that's a valid URI for git (`http`, `https`, `git` or `ssh`) is
  treated as a remote git directory that will be fetched. You can set a
  specific tag or branch in the fragment part of the URI, e.g.:

        https://example.com/dibspacks/whatever#v42



## Configuration






The process goes along some stages:

- *fetch* the code
- *build* it, generating a tarball
- *bundle* the tarball in a docker image
- *ship* the docker image to relevant registries

## Directories

There is a project directory with a file `dibs.yml` inside, with
relevant configurations and sub-directories to perform the different
stages. Each project has the following structure:

    <PROJECT_DIR>
        - dibs.yml
        - dibspacks
        - cache
        - env
        - src

The only necessary file that has to be there is `dibs.yml`, the rest
will be created.

## Resolving *dibspack*s

On the command line you can set option `--dibspack` (aliased `-D`),
possibly multiple times:

    $ dibs -D "$URL1" -D "$URL2" ...

If absent, environment variable `DIBS_DIBSPACK` is inspected. It can
only carry one single `dibspack` though:

    $ DIBS_DIBSPACK="$URL1" dibs ...

If none of the above are present, a file `.dibspacks` in the source root
is looked for, with a list of one URI per line.

URIs can be... also not strict URIs:

- `http`/`https`/`git` URIs do what you think
- paths starting with `dibspacks` are relative to the `dibspacks`
directory, where you can put your project-specific dibspacks
- paths starting with `src` are relative to the `src` directory, where
you can put source-specific dibspacks
- absolute paths are intended with respect to the container, so most of
the times it will be addressing something that you expect to be already
in the base image.

If `.dibspacks` is a directory, each sub-directory is a candidate
dibspack and will be used.

Otherwise... it's an error!

## Using *dibspack*s

The build/bundle phases are driven by one or more *dibspack*s, an idea
that is drawn directly from Heroku's buildpacks.

The *dibspack* is supposed to have the following structure:

    <DIBSPACK_DIR>
        - bin
            - build-detect
            - build
            - bundle-detect
            - bundle

There are some "reference" directories that will be passed to the
different scripts via positional parameters, in the following way:

    build-detect  "$SRC_DIR" "$CACHE_DIR" "$ENV_DIR"
    build         "$SRC_DIR" "$CACHE_DIR" "$ENV_DIR"
    bundle-detect "$SRC_DIR" "$CACHE_DIR" "$ENV_DIR"
    bundle        "$SRC_DIR" "$CACHE_DIR" "$ENV_DIR"

- `SRC_DIR` is where the originally checked out code will be available.
It is set read-only for all except `bin/build`.

- `CACHE_DIR` is where you can put stuff that you want to preserve,
possibly across different build/bundle phases to improve your
build/bundle overall time. For detect scripts it is read-only, otherwise
it is read-write.

- `ENV_DIR` is where some environment variables of the *run* phase will
be put, if any. It is up to `bin/build` or `bin/bundle` to import them
if needed, although this is discouraged because they belong to the *run*
phase. It is always passed read-only.

## Fetch

Code ends up in the `src` subdirectory of the project directory.

This can be done in different ways (not all supported initially):

    - git: either local repo or remote
    - tar: either local file or remote
    - dir: a directory taken as a base
    - none: the `src` directory is edited directly

## Build

This uses a mechanism similar to Heroku's buildpacks, with *dibspack*s.
The dibspack can be set in the configuration file for dibs, in the
environment variable `DIBSPACK_URL` or in a `.dibspacks` file in the
`src` directory.

The structure is similar to that of buildpacks, apart that as of now
only `detect` and `build` are supported. The first assesses whether the
dibspack is suitable, the other does the build itself.

The two scripts SHOULD be executable within the selected image, hence
it's probably better to rely on POSIX shell only and in case instal
further tools from there.

### Detection step

The `bin/build-detect` script is passed one single parameter `SRC_DIR`, where
the code is already available. Exit code `0` means that the dibspack is
suitable for building, any other value skip the buildpack.

### Build step

The `bin/build` script in the *dibspack* is passed all positional
parameters.

## Bundle

The bundle phase takes the build output tarball and generates a Docker
image out of it.

It again uses the same *dibspack* mechanism, in a detect-then-bundle
way. Whatever is the state of the container at the end... is packaged.

### Detection step

The `bin/bundle-detect` is passed one single parameter `SRC_DIR` where
the stuff to install resides.

### Installation step

The `bin/bundle` script in the *dibspack* is passed all positional
parameters.

The installation might be as simple as a copy or something more
complicated. You choose!

### Bundling step

After the installation is completed, the container is stopped and
additional configurations applied (up to a full Dockerfile). The outcome
is tagged for shipping.


## Practical Considerations on Build/Bundle

You have total control about what happens in the build/bundle phases,
but their separation is to help you out with the following problems:

- build usually needs a set of tools (e.g. compilers) that are then not
necessary when running the container. Separating the two phases allows
you to include those tools in the build phase, and leave them out in the
bundle phase.

- some programs/libraries might insist on being installed in specific
positions. E.g. you are encouraged to end up with all your application
in `/app`, much like herokuish. The presence of the `CACHE_DIR` should
be leveraged to reach this goal, e.g. a build/bundle pattern might be:

    # in dibspack's bin/build
    mkdir "$CACHE_DIR/app"
    ln -s "$CACHE_DIR/app" /app
    # install all things inside /app now...

    # in dibspack's bin/bundle
    mkdir /app
    cp -pPR "$CACHE_DIR/app" /app


