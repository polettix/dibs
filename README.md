# dibs - Docker image build system

`dibs` aims at automating the process from code to Docker image, with
flexibility as to the base images used (mainly to enable building on top
of Alpine Linux).

The assumption is that there is a project directory with a file
`dibs.yml` inside, with relevant configurations.

The process goes along some stages:

- *fetch* the code
- *build* it, generating a tarball
- *bundle* the tarball in a docker image
- *ship* the docker image to relevant registries

## Directories

There are some "reference" directories that will be passed to the
different scripts via positional parameters:


- `SRC_DIR` is where the originally checked out code will be available.
It is the only directory that is passed to all commands, and it always
comes first

- `CACHE_DIR` is where you can put stuff that you want to preserve,
possibly across different build/bundle phases to improve your
build/bundle overall time. When present, it always comes second

- `ENV_DIR` is where some environment variables will be put, it will be
up to you to import or ignore them. When present, it always comes third.
The environment variables SHOULD be the ones that will eventually be
used for running, so a really clean build/bundle is expected to ignore
them! Variables meant to influence the build/bundle process itself will
be passed in the environment, directly.


## Fetch

Code ends up in the `src` subdirectory of the project directory.

This can be done in different ways:

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


