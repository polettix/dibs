[//]: # vim: ts=4 sts=4 sw=4 et ai colorcolumn=79 tw=78 :

# dibs - Docker image build system

`dibs` aims at automating the process from code to Docker image, with
flexibility as to the base images used (mainly to enable building on top of
Alpine Linux). To some extent, it can be seen as an alternative to using a
[Dockerfile][], with the difference that `dibs` provides finer control over
the different phases and might completely ditch intermediate containers during
the process.

`dibs` itself is a driver program that does nearly nothing... or better:

- supports a sophisticated way of providing configurations
- iterates over steps defined in the configuration
- automates lookup of code to execute in each step, calling `docker` when
  needed and saving images along the way, when requested to do so
- automates rollback of saved images if something goes wrong

## Introduction

First things first: why `dibs`? The main need is to pack a Docker
container image starting from some code, much like what can be done with
a [Dockerfile][]... let's look at a few problems and how `dibs` addresses
them.

### Trimming Container Images

Just putting the code inside a container is not sufficient, because...

- ... it probably needs a runtime environment (Perl, Java, Python, ...)
  inside the image too
- ... it might need additional pre-requisites in form of other software or
  libraries
- ... it might need to have some parts compiled or undergo a *build* process
- ... it will probably need the container to be set so that the invocation of
  the program is eased.

The build process usually requires tools (like a compiler, C<make>,
development versions of libraries, etc.) that are rarely needed during the
runtime phase. With a single [Dockerfile][], there are two choices:

- keep the tools around, or get rid of them while still having a *fat*
  image (due to how filesystem overlays work, what is *deleted* in a layer
  only hides it from lower layers, but the space is still needed)
- install the tools and remove them in the same phase of the
  [Dockerfile][], thus making it difficult to cache or pinpoint the tools
  themselves.

The idea behind `dibs` is that the path from the code to the Docker image
can be broken into *steps*:

- each step runs a sequence of operations that stack upon a container
  image much like a [Dockerfile][]
- different steps can pass artifacts around thanks to some shared
  directories
- only the containers of the steps of interest are kept, others are thrown
  away.

For example, a *build, then bundle* process might be broken into two steps
like this:

      _____________     +-------------+
     /             \    |             | - start from "build"-ready image
     | Shared dirs |----| Build Step  | - compile in container
     | ----------- |    |             | - save in cache
     |             |    +-------------+
     |       src - |    
     |     cache - |    +-------------+
     |       env - |    |             | - start from "runtime"-ready image
     |       ... - |----| Bundle Step | - copy artifacts from cache
     \_____________/    |             |   to destination
                        +-------------+ - set up entry point


In this way, *build* operations can be performed in the context of
a *heavier* container image, while the *bundle* operation relies on
a *leaner* starting container image, providing a *leaner* result.


### Reuse of operations

Another common problem with [Dockerfile][]s has to do with how container
images are customized, e.g. to execute build/bundle operations.

The [RUN][] directive in the [Dockerfile][] is surely very powerful, but
it allows you to execute either direct commands or some script/program
that you made somehow visible inside the container during its
construction. While very powerful (it's actually all that is strictly
needed), it's quite difficult to reuse operations consistently.

`dibs` draws inspiration from how [Heroku][] addressed this problem, i.e.
[buildpacks][]. Much in the same spirit, `dibs` leverages *dibspacks* to
accomplish operations; these can be shared and loaded easily and
automatically, so that the user only has to select and configure the right
ones.


## Basics

Some basic concepts to understand how to use `dibs`.

### Directory Layouts

`dibs` assumes that there is a *project directory* where things are kept
nicely. The basic structure of a project is the following:

    <PROJECT_DIR>
        - cache
        - dibs.yml
        - dibspacks
        - env
        - src

`dibs` expects to find a configuration file. By default, it's the `dibs.yml`
file you see in the directory structure above, but you have means to provide
an alternative one.

To be completely fair, the layout above is not the only one out of the box.
That is the way to go if there is a clear separation between the development
and the packaging phases (e.g. different teams, or setting up a generic system
like [Heroku][] or [Dokku][]), because it will be up to the packaging *team*
to make sure that the code to use for building the image ends up in the `src`
directory.

If simplicity is preferred (e.g. for single-person developments, or small
teams), it is also possible to work in *local* mode and have a slighly
different layout:

    <SOURCE_DIR>
        - dibs.yml
        - .dibs
            - cache
            - dibspacks
            - env

Here, the role of `PROJECT_DIR` is taken by the sub-directory `.dibs`, with
the exception that the code is at the root of the whole setup. As a matter of
fact, it's not even necessary to create the `.dibs` directory in this case,
because `dibs` will do this as needed.

Whatever the layout, anyway, the following directories are of interest:

- *project* directory (`<PROJECT_DIR>` or `.dibs` in the two layouts) is a
  basecamp for `dibs` operations
- *source*  directory (`src` or `<SOURCE_DIR>` in the two layouts) is where
  the source code is
- `cache` is a read-write directory that is available through all steps of a
  `dibs` run, as well as different invocations, and useful for passing
  artifacts through the different stages
- `env` is a read-only directory that might be useful to have around
- `dibspacks` is where most of the dibspacks will be available (either coded
  directly, or automatically downloaded via [Git][])

### Dibspacks

The actual operations are performed through *dibspack*s. The starting idea is
taken from [Heroku][]'s [buildpacks][], but there is actually little
resemblance left as of now.

A *dibspack* is a program (whose location can be specified flexibly); this
program can be used to perform an action within a container. This is more or
less what the `build` program in a buildpack is for; the other programs are
not supported (either because they can be embedded in the main dibspack
program, like `detect`, or because they are not used by `dibs`).

The program will be executed inside containers. The resulting container is
then used as a base for further dibspacks executions inside the same step and
also for saving a final image (if so configured).

Each *dibspack* is passed some command line arguments. The first three are
*always* the same, namely (in order):

- the absolute path to the *source* directory from within the container;
- the absolute path to the cache directory, from within the container;
- the absolute path to the env directory, from within the container.

It's the same as what is provided to the `build` program of a
[buildpack][buildpacks]. `dibs` also allows passing additional arguments
though, whose definition and semantics are specific to each dibspack.

Dibspacks can be located in many different positions:

- within the `dibs.yml` file itself
- inside the `dibspacks` directory (that is also available inside the
  container, although its position is not passed on the command line)
- in some location inside the source directory
- in a git repository, either local or remote

Depending on the type of dibspack, `dibs` will first fetch the associated code
and then run it, all automatically. For a collection of basic dibspack, it's
possible to look at the [dibspack-basic][] repository. A simple example
program might be the following (assuming that the build tools are already
available in the container):

    #!/bin/sh
    src_dir="$1"
    cache_dir="$2"

    cd "$src_dir" &&
    rm -rf local &&
    cp -a "$cache_dir/local" . &&
    carton install --deployment &&
    rm -rf "$cache_dir/local" &&
    cp -a local "$cache_dir"


## Source

Depending on which *mode* is set, the directory layout is different.

In *external* mode (default), the layout is the following:

    <PROJECT_DIR>
        - cache
        - dibs.yml
        - dibspacks
        - env
        - src

The `src` directory is assumed to be populated by some means, e.g. be already
there thanks to some external program, or fetched as part of a *dibspack*'s
operation (the source directory is mounted read-write). For example, the
[git/fetch][] program can be used to fetch a remote [Git][] repository, but it
might also be that the development happens directly inside `src`.

In *local* mode (triggered with command-line option `--local` or its shortcut
alias `-l`), instead, the root is assumed to be the source directory itself,
so it's assumed to be already there. This can be useful when doing local
development, for example, with local generation of images.


## Dibspacks

Dibspacks are at the real core of `dibs`; it would be able to do very little
without. We already touched upon what a dibspack is: a program to execute some
task.

`dibs` supports different ways for you to configure the location of dibspacks,
which should cover a wide range of needs. They are documented in the
documentation for `dibs` so the full explanation will not be repeated here.

Dibspacks taken from `git` are saved inside the `dibspacks/git` directory.
Although it's not mandatory, it's probably better to put *local* dibspacks
inside another sub-directory, e.g. `dibspacks/local` or so.

Dibspacks of the *immediate* type (i.e. where the program is provided inside
`dibs.yml` itself) are saved inside `dibspacks/immediate`, so in this case too
it's wise to avoid hitting that.

Dibspack programs are invokes like this:

    <program> <src> <cache> <env> [args from dibspack configuration...]

Example:

    whatever.sh /tmp/src /tmp/cache /tmp/env what ever

The first three arguments are paths to the associated directories in the
project directory, but "seen" from inside the container. In particular:

- `src` and `cache` are available in read-write mode;
- `env` is always set read-only.

The directories are usually mounted under `/tmp` like in the example, so you
should avoid using them otherwise. This might change in the future.
Additionally, the `dibspacks` directory is mounted too as `/tmp/dibspacks`,
read-only; you should not use this directory directly, unless you know what
you are doing and accept that this may change in the future.

A full selection of dibspacks can be found in [dibspack-basic][].

## Configuration

The configuration is kept, by default, inside YAML file `dibs.yml`; it's
possible to change this though, so that multiple alternative configurations
can be kept in the same place.

The structure is described in detail in `dibs`'s documentation, so we will
concentrate on examples here.

A rather simple but possibly effective configuration file is the following:

    ---
    name: example-project
    defaults:
        dibspacks:
            basic:
                type:   git
                origin: https://github.com/polettix/dibspack-basic.git
                user:   user
            prereqs:
                type:   git
                origin: https://github.com/polettix/dibspack-basic.git
                path:   prereqs
                user:   root
    steps:
        - build
        - bundle
    definitions:
        build:
            from: fat-build-image:tag
            dibspacks:
                - default: prereqs
                  args: build
                - default: basic
                  path: perl/build
                - default: src
                  user: user
                  path: dibs/copy-app-into-cache.sh
        bundle:
            from: lean-running-image:tag
            keep: yes
            entrypoint: ['/runner']
            cmd: []
            tags:
                - latest
            dibspacks:
                - default: prereqs
                  args: bundle
                - default: src
                  user: user
                  path: dibs/copy-app-from-cache.sh

There are a few assumptions in the `dibs.yml` file above, but it can
actually work if:

- images `fat-build-image:tag` and `lean-running-image:tag` already exist
  and contain, respectively, the build tools and the runtime elements
  (including a `/runner` program that is used as entry-point)
- the source directory contains a `dibs` sub-directory and the relevant
  scripts inside, doing what the advertise in their names.

In this way it's possible to prepare (and maintain) a build and a bundle
images, and leverage them for doing the actual needed work, generating
a lean output Docker image.

## Running

When run, `dibs` looks for the steps to be executed, and runs them.

In particular, each step is run stacking on top of an evolving container,
much like in the [Dockerfile][] case. Whether to keep or ditch the end
result is a choice that is made inside the `dibs.yml` file through the
`keep` option.

Different steps are run one after the other, but in independent containers
that potentially root from different starting images, like in the example
above in the configuration section.

The documentation for `dibs` has the detail on all command line options,
although it's probably important to remember that `--local` allows
selecting between the *local* mode (when present) or the *external* mode
(when absent from the command line).

This allows implementing many different workflows, e.g.:

- define one or more *build* phases that leverage images/dibspacks that
  include build tools, like a compiler;
- save the outcome of that/those phases in the `cache` directory
- define a *bundle* phase where that outcome is fit inside a *release* image
  that only contains the needed tools for running (but does not include
  building tools)


## Examples

`dibs` allows taking a flexible approach to building images, which might be
overwhelming. Here are a few examples that might apply in different
situations.

### `dibs` itself

This was the `dibs.yml` file for building the `dibs` image at some stage
of its life:

    01	---
    02	name: dibs
    03	logger:
    04	   - Stderr
    05	   - log_level
    06	   - info
    07	steps:
    08	   - build
    09	   - bundle
    10	defaults:
    11	   variables:
    12	      - &base_image 'alpine:3.6'
    13	      - &version 'DIBSPACK_SET_VERSION="0.001972"'
    14	   dibspack:
    15	      basic:
    16	         type:   git
    17	         origin: https://github.com/polettix/dibspack-basic.git
    18	         user:   user
    19	      prereqs:
    20	         type:   git
    21	         origin: https://github.com/polettix/dibspack-basic.git
    22	         path:   prereqs
    23	         user:   root
    24	      user: &user
    25	         type: src
    26	         name: add user and enable for docker
    27	         user: root
    28	         path: dibspacks/user-docker.sh
    29	definitions:
    30	   builder:
    31	      from: *base_image
    32	      keep: yes
    33	      name: 'dibs-builder'
    34	      tags: [ 'latest' ]
    35	      dibspacks:
    36	         - *user
    37	         - default: prereqs
    38	           args: build
    39	   runner:
    40	      from: *base_image
    41	      keep: yes
    42	      name: 'dibs-runner'
    43	      tags: [ 'latest' ]
    44	      dibspacks:
    45	         - *user
    46	         - default: prereqs
    47	           args: bundle
    48	   build:
    49	      from: 'dibs-builder:latest'
    50	      keep: no
    51	      dibspacks:
    52	         - default: prereqs
    53	           args: build
    54	         - 'src:dibspacks/src-in-app.sh'
    55	         - default: basic
    56	           path: perl/build
    57	           args: ['/app', *version]
    58	         - default: basic
    59	           path: install/with-dibsignore
    60	           args: '--src /app --dst @path_cache:perl-app'
    61	   bundle:
    62	      from: 'dibs-runner:latest'
    63	      keep: yes
    64	      name: dibs
    65	      tags: [ 'latest' ]
    66	      entrypoint: [ '/dockexec', 'user', '/profilexec', '/app/bin/dibs' ]
    67	      cmd: [ '--help' ]
    68	      dibspacks:
    69	         - default: prereqs
    70	           args: bundle
    71	         - default: basic
    72	           user: root
    73	           path: wrapexec/install
    74	           args: ['dockexec', 'profilexec']
    75	         - default: basic
    76	           path: install/plain-copy
    77	           args: '@path_cache:perl-app /app'
    78	           user: root

This leverages both remote and local dibspacks. The following sub-sections
add some considerations on the above example.

#### Defaults

The `defaults` section has two sub-sections, one (`variables`) used
internally in a *YAML-way*, the other one (`dibspack`) consumed by `dibs`:

- `variables` concentrates some values that can be reused later in the
  YAML file; for this reason, its items are preceded by a label
  (`base_mage` and `version`). Concentrating values here allows easier
  maintenance and enhances readability. The `version` *variable* is set in
  the way it will eventually consumed, but this depends on the dibspack of
  course.

      11	   variables:
      12	      - &base_image 'alpine:3.6'
      13	      - &version 'DIBSPACK_SET_VERSION="0.001972"'

- `dibspack` sets a few commodity configurations for later reuse inside
  definitions. Most of the activities are performed leveraging
  [dibspack-basic][], so it's easier to define it here once and for all.
  `prereqs` will be reused by all steps, so it gets a *factored*
  definition too. Last, both the base images `builder` and `runner` will
  define a `user` to avoid running as `root`, so the relevant definitions
  are factored here as well. In this case, the default is also assigned
  a YAML label for later direct reuse.

      14	   dibspack:
      15	      basic:
      16	         type:   git
      17	         origin: https://github.com/polettix/dibspack-basic.git
      18	         user:   user
      19	      prereqs:
      20	         type:   git
      21	         origin: https://github.com/polettix/dibspack-basic.git
      22	         path:   prereqs
      23	         user:   root
      24	      user: &user
      25	         type: src
      26	         name: add user and enable for docker
      27	         user: root
      28	         path: dibspacks/user-docker.sh

#### Structure

The definition contains four definitions, two for *base images*, one for
building the code and the last one for bundling the final output image.

- `builder` is the base image used for building. The final container is
  preserved (`keep` set to `yes`) but it is assigned a specific name
  (`dibs-builder`) to avoid overlapping with the main image of interest.
  The main goal if this image is to pre-bake most of the requirements
  (which should change slowly in time) and make sure there is the right
  user in the image.

      30	   builder:
      31	      from: *base_image
      32	      keep: yes
      33	      name: 'dibs-builder'
      34	      tags: [ 'latest' ]
      35	      dibspacks:
      36	         - *user
      37	         - default: prereqs
      38	           args: build

- `runner` serves a purpose much similar to `builder`, but will be used as
  base for the bundled image by definition in `bundle`. Note that the
  pre-baking of pre-requisites concentrates on `bundle` instead of
  `build`; this allows the `prereqs` dibspack inside [dibspack-basic][] to
  pick the right pre-requisites for running instead of building.


      39	   runner:
      40	      from: *base_image
      41	      keep: yes
      42	      name: 'dibs-runner'
      43	      tags: [ 'latest' ]
      44	      dibspacks:
      45	         - *user
      46	         - default: prereqs
      47	           args: bundle

- `build` leverages the *fatter* image output from `builder` to do the
  compilation and building steps. It's the most complex of the
  definitions, and also the one whose container is eventually thrown away,
  thanks to the call to `install/with-dibsignore` that saves the relevant
  parts in the cache.

      48	   build:
      49	      from: 'dibs-builder:latest'
      50	      keep: no
      51	      dibspacks:
      52	         - default: prereqs
      53	           args: build
      54	         - 'src:dibspacks/src-in-app.sh'
      55	         - default: basic
      56	           path: perl/build
      57	           args: ['/app', *version]
      58	         - default: basic
      59	           path: install/with-dibsignore
      60	           args: '--src /app --dst @path_cache:perl-app'


- `bundle` starts from where `build` left off, but this time in the
  *leaner* image output by `runner`. The installation of the `dockexec`
  and `profilexec` programs might be moved inside the `runner` as it's
  something that will not change significatively in time; here it's left
  to enhance readability when setting the `entrypoint`.

      61	   bundle:
      62	      from: 'dibs-runner:latest'
      63	      keep: yes
      64	      name: dibs
      65	      tags: [ 'latest' ]
      66	      entrypoint: [ '/dockexec', 'user', '/profilexec', '/app/bin/dibs' ]
      67	      cmd: [ '--help' ]
      68	      dibspacks:
      69	         - default: prereqs
      70	           args: bundle
      71	         - default: basic
      72	           user: root
      73	           path: wrapexec/install
      74	           args: ['dockexec', 'profilexec']
      75	         - default: basic
      76	           path: install/plain-copy
      77	           args: '@path_cache:perl-app /app'
      78	           user: root

The `builder` and `runner` definitions might be avoided and merged
respectively inside `build` and `bundle`. Keeping them separate allows
reducing the time for installing pre-requisites, which is a form of
controlled caching.

#### Steps

The `steps` section only runs for `build` and `bundle` because these are
the *recurrent* operations. These two definitions leverage on the presence
of `dibs-builder:latest` and `dibs-runner:latest` though, so they will
need to be generated (or pulled) before this `dibs.yml` can be used out
the box.

Generating the images is easy anyway, because the `dibs.yml` file contains
the relevant definitions:

    $ dibs --local --steps builder,runner

After this, the regular *build&bundle* process can be run simply as this:

    $ dibs --local

#### Shortcut syntax for dibspacks

Line 54 shows a shortcut syntax for including a dibspack in the list for
a definition:

    48	   build:
    49	      from: 'dibs-builder:latest'
    50	      keep: no
    51	      dibspacks:
    52	         - default: prereqs
    53	           args: build
    54	         - 'src:dibspacks/src-in-app.sh'
    55	         - default: basic
    56	           path: perl/build
    57	           args: ['/app', *version]
    58	         - default: basic
    59             ...

The shortcut syntax is equivalent to the following:

    # type is src, i.e. the path below is relative to the source
    type: src
    path: dibspacks/src-in-app.sh

This syntax is available also for types `project` and `src`. 

Dibspacks of type `git` have a shortcut syntax too, which amounts to
providing just the URI to the repository (optionally followed by `#` and
the ref to checkout). In this case, the repository is supposed to contain
a program called `operate` in the root directory, which will eventually be
called as entry point of the dibspack.

Dibpacks of type `immediate` have no shortcut syntax.

#### Providing `args` to a dibspack

The arguments passed to a dibspack during invocation are:

    program src_dir cache_dir env_dir [other args..]

The *other args* can be set using the `args` key in the associative array
defining the dibspack. This points to a list of elements, that can be either
plain scalars (e.g. strings or numbers), passed verbatim, or associative
array allowing you to retrieve some data from `dibs`.

If you're just looking for a few examples, the following should all work:

    args:
      - path:               # referred to cache
          cache: perl
      - path_cache: perl    # ditto, shortcut
      - '@path_cache:perl'  # ditto, string-only shortcut
      - path_src: /prereqs  # referred to src, even with initial /
      - '@path_src:/prereqs' # ditto
      - path_env: /some
      - path_dibspacks: build
      - type: path          # ditto
        cache: perl
      - type: step_id       # key of step in definitions
      - type: step_name     # "step" field in definition, defaults to key

The arguments can also be provided as a single string, which is where the
string-shortcuts come handy. The following:

    args: '@path_cache:perl-app /app'

is equivalent to:

    args:
        - path:
            type: path
            cache: perl-app
        - '/app'

but much easier to type.

The *full* way of setting a special parameter is like this:

    args:
      - type: some_type
        this: that
        another: argument

The available `type`s are:

- `path`: allows to resolve a path within the container, referred to a
  specific base directory. For example:

      args:
        - path:
            cache: /whatever

  is resolved to the `whatever` sub-directory of wherever the cache directory
  happens to have been mounted inside the container. In addition to `cache`,
  you can set paths relative to `dibspacks`, `env` and `src`.

- `step_id`: the identifiers of the dibspack inside the `definition`
  associative array

- `step_name`: whatever was set as `step` parameter inside the dibspack
  definition

Additionally, you can also use the shorthands `path_cache`,
`path_dibspacks`, `path_env` and `path_src`, which are turned into the right
`path` definition. For example, the following argument expansions will provide
the same path:

    args:
      - path:
          cache: /whatever
      - path_cache: /whatever

It's easy to forget to associate a value to `step_id` and `step_name`, because
they actually need no option. In this case, the suggestion is to set them
through `type`, like in the following example:

    args:
      - type: step_id
      - type: step_name
      - path_cache: whatever

#### Setting defaults

If a dibspack is reused over and over (e.g. leveraging a suite of
dibspacks collected in a single git repository, much like
[dibspack-basic][], it comes handy to set entries in the
`defaults.dibspack` section of the configuration file:


   dibspack:
      basic:
         type:   git
         origin: https://github.com/polettix/dibspack-basic.git
         user:   user
      prereqs:
         type:   git
         origin: https://github.com/polettix/dibspack-basic.git
         path:   prereqs
         user:   root
      user: &user
         type: src
         name: add user and enable for docker
         user: root
         path: dibspacks/user-docker.sh

and later use them, like this (leveraging YAML ancors):

    definitions:
        builder:
            # ...
            dibspacks:
                - *user

or this, leveraging `dibs` internal system for handling defaults (via the
`default` keyword:

    definitions:
        ...
      bundle:  
          dibspacks:
             - default: prereqs
               args: bundle
             - default: basic
               user: root
               path: wrapexec/install
               args: ['dockexec', 'profilexec']
             - default: basic
               path: install/plain-copy
               args: '@path_cache:perl-app /app'
               user: root

### Environment Variables Handling

It is possible to specify environment variables in multiple places; the
following list gives the priority (the higher in the list, the more it takes
precedence):

- variables `DIBSPACK_FROM_IMAGE` and `DIBSPACK_WORK_IMAGE` are set by `dibs`
  and indicate respectively the image in the `from` field of the dibspack and
  its current alias (or evolution) in the dibs step

- other metadata dynamically generated by `dibs`, at the moment:

    - `DIBS_ID`, generated from the timestamp and the `dibs` invocation
      process id

- whatever appears in the dibspack's `env` field

- whatever appears in the step's `env` field

- whatever appears in the `default.env` section of the configuration file.

Environment variaables can be specified in multiple ways:

- as lists of variables definition (recursive)

- as associative arrays: keys are environment variable names, values are the
  associated values. Undefined values are taken from the `dibs` environment.

- as plain scalars, which are interpreted as variable names whose value is
  taken from the `dibs` environment.

Example:

    default:
      env:
        - THIS
        - THAT: value
          ANOTHER: ~
    definitions:
      first:
        env:
          - THIS: a-value
          - ANOTHER: some-value
        dibspacks:
          - name: dp1
            env:
              - THIS: different-value
            # ...
          - name: dp2
            env:
              - FOO: baz
      second:
        env:
          - FOO: bar

In this case:

- dibspack `dp1`:
    - `THIS` takes value `different-value`
    - `ANOTHER` takes value `some-value`
    - `THAT` takes value `value`

- dibspack `dp2`:
    - `THIS` takes value `a-value`
    - `ANOTHER` takes value `some-value`
    - `THAT` takes value `value`
    - `FOO` takes value `baz`

- dibspacks in `second`:
    - `THIS` takes value from `dibs`'s environment
    - `ANOTHER` takes value from `dibs`'s environment
    - `THAT` takes value `value`
    - `FOO` takes value `bar`



[Perl]: https://www.perl.org
[Log::Any]: https://metacpan.org/pod/Log::Any
[Docker]: https://www.docker.com/
[CMD]: https://docs.docker.com/engine/reference/builder/#cmd
[ENTRYPOINT]: https://docs.docker.com/engine/reference/builder/#entrypoint
[RUN]: https://docs.docker.com/engine/reference/builder/#run
[dibspack-basic]: https://github.com/polettix/dibspack-basic
[Dockerfile]: https://docs.docker.com/engine/reference/builder/
[buildpacks]: https://devcenter.heroku.com/articles/buildpacks
[Heroku]: https://www.heroku.com/
[Dokku]: http://dokku.viewdocs.io/dokku/
[Git]: https://git-scm.com/
[dibspack-basic]: https://github.com/polettix/dibspack-basic
[git/fetch]: https://github.com/polettix/dibspack-basic/blob/master/git/fetch
