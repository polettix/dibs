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

`dibs` draws inspiration from how Heroku addressed this problem, i.e.
[buildpacks][]. Much in the same spirit, `dibs` leverages *dibspacks* to
accomplish operations; these can be shared and loaded easily and
automatically, so that the user only has to select and configure the right
ones.


## Basics

`dibs` assumes that there is a *project directory* where things are kept
nicely. The basic structure of a project is the following:

    <PROJECT_DIR>
        - cache
        - dibs.yml
        - dibspacks
        - env
        - src

`dibs` expects to find a configuration file. By default, it's the `dibs.txt`
file you see in the directory structure above, but you have means to provide
an alternative one. More on how to set the configuration can be found down in
section *Configuration*.

The actual operations are performed through *dibspack*s. The starting idea is
taken from Heroku's buildpacks, but there is actually little resemblance left
as of now. A dibspack is a program (whose location can be specified flexibly);
this program can be used to perform an action within a container. This is more
or less what the `build` program in a buildpack is for; the other programs are
not supported (either because they can be embedded in the main dibspack
program, like `detect`, or because they are not used by `dibs`).

The program will be executed inside containers. The resulting container might
then be used as a base for further dibspacks executions and also for saving a
final image (or more).

For using `dibs` you have to:

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
without. We already touched upon what a dibspack is: a program to execute some
task.

`dibs` supports different ways for you to configure the location of dibspacks,
which should cover a wide range of needs:

- the most natural place to define a list of dibspacks is in each step's
  configuration in the `dibs.yml` file (or whatever you are going to use)

- as a fallback, they might be defined directly in your code, i.e. inside
  `src/.dibspacks`. There are two sub-alternatives here:

    - if `.dibspacks` is a file, then it is loaded as a YAML file and expected
      to contain a mapping between step names and dibspacks (either single
      ones, or lists of them)

    - if `.dibspacks` is a directory, each sub-directory is a dibspack that
      matches the name of a corresponding step, containing dibspacks inside.
      In this case, "hidden" files (i.e. whose name starts with `.`) or
      starting with `_` are ignored, to let you put additionall stuff in
      there.

FIXME: double check code for src/.dibspacks

Locations can have different shapes:

- anything that's a valid URI for git (`http`, `https`, `git` or `ssh`) is
  treated as a remote git repository that will be fetched. You can set a
  specific tag or branch in the fragment part of the URI, e.g.:

        https://example.com/dibspacks/whatever#v42

- anything that starts with the string `project:` is a path resolved
  relatively to the `dibspacks` sub-directory in the project directory

- anything that starts with the string `src:` is a path resolved inside the
  `src` directory in the project, which is also the reference directory where
  the source code is (i.e. dibspacks that fetch your code should put it there)

- anything else generates an exception!

Dibspacks taken from `git` are saved inside the `dibspacks/git` directory.
Although it's not mandatory, it's probably better to put *local* dibspacks
inside another sub-directory, e.g. `dibspacks/local` or so.

FIXME add object-style definition of dibspacks
FIXME specify that git dibspacks can optionally specify a path

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

## Configuration

The configuration is kept, by default, inside YAML file `dibs.yml`. The
structure is described in detail in a later section, but it might be as simple
as this if your dibspacks have sensible defaults:

    ---
    name: your-project-name
    steps:
        - build
        - bundle
    definitions:
        build:
            from: some-image:tag
            dibspacks:
                - src:pre-build
                - https://example.com/prereqs#v42
                - https://example.com/builder#v72
                - project:build
                - src:build
        bundle:
            from: some-image:tag
            keep: yes
            entrypoint:
                - /runner
            cmd: []
            tags:
                - latest
            dibspacks:
                - https://example.com/prereqs#v42
                - https://example.com/bundler#v72
                - project:bundle
                - https://example.com/runner#v37

## Running

When you run `dibs`, by default it uses the current directory as the project
directory and looks for `dibs.yml` inside. It then executes all the `steps` in
order:

- for each step, the associated dibspacks are detected
- in the step, the dibspacks are executed as a sequence of containers:
    - the first one is started based on the image set with `from`
    - the following ones from the freezing of the previous container
- after each step, if the associated definition has `keep` set, the container
  image is kept and additional `tags` are added, otherwise it is dropped (e.g.
  after saving something inside `cache`).

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

### Small Project

In a small project, you probably want to keep things as simple and compact as
possible. Especially if your project does not take much to build and bundle,
you will probably not need much caching and so you can do with one single
`dibs.yml` file and only one step.

As an example, consider the following `dibs.yml` file:

    ---
    name: mojo-example
    steps:
       - build
       - bundle
    definitions:
       build:
          from: 'alpine:3.6'
          dibspacks:
             - type: git
               origin: 'https://github.com/polettix/dibspack-basic.git'
               path: prereqs
             - 'project:perl/build'
       bundle:
          from: 'alpine:3.6'
          dibspacks:
             - type: git
               origin: 'https://github.com/polettix/dibspack-basic.git'
               path: prereqs
             - 'project:perl/bundle'
             - type: git
               origin: 'https://github.com/polettix/dibspack-basic.git'
               path: procfile
          keep: yes
          tags:
             - latest
          entrypoint: 
             - '/procfilerun'
          cmd: []

This leverages both remote and local dibspacks. At every run, both the build
and the bundle images are re-built from scratch, adding prerequisites, doing
dependencies installations, etc.


## Configuration: Details

This section aims at explaining all the features and capabilities that can be
leveraged through the `dibs.yml` file.

The YAML file is structured as an associative array. The keys below are
*supported*, in the sense that they have a meaning for `dibs`; it is anyway
possible to add more keys as needed.

Recognized keys are:

- `defaults`: an associative array setting defaults that apply over the
  specific call to `dibs`. More details below in the specific section.

- `definitions`: an associative array, mappingpossible `steps` and their
  contents. The keys set the name of the possible `steps`.

- `logger`: a list of parameters for [Perl][] module [Log::Any][]. This part
  is currently not entirely fleshed out, although it's possible to set the
  logging level to make `dibs` more or less verbose.

- `name`: the name of the project. It is mostly used as the default image
  name, but it can be overridden in the `definitions`.

- `steps`: a sequence of steps to take. Each step MUST have a definition
  inside section `definitions`


### Annotated Example `dibs.yml`

An annotated example `dibs.yml` file is below:

    # name of our dibs project
    name: examploid

    # set run-wide defaults
    defaults:

        # setting defaults for dibspacks allows to "recall" those defaults
        # and avoid typing. The sub-keys are just names/identifiers that can
        # then be used to recall the defaults in the dibspacks sections inside
        # definitions.
        dibspack:
            basic: # this is a real git repository with many dibspacks inside
                type:   git
                origin: https://github.com/polettix/dibspack-basic.git

        # these environment variables are run-wide, passed to every invocation
        # of dibspacks
        env:
            - THIS  # this is "imported" from the current environment
            - THAT: 'has a value'

    # this is where you define what is performed in the different steps.
    # Sub-keys are names/identifiers that can the be used/reused inside the
    # steps section. We will define two of them, one for building our code and
    # one for packing ("bundle") it.
    definitions:

        build:

            # the base image. You might of course prepare a build image and
            # skip some of the steps, e.g. by setting up an image that already
            # has build tools (compiler, make, etc.) inside. Here we will
            # start almost from scratch.
            from: 'alpine:3.6'

            # a list of dibspacks to apply in order
            dibspacks:

                # each dibspack does a specific job, or is supposed to. You
                # can recall common parameters from the defaults section above
                # using the `default` key, and then specialize/override
                # parameters as needed. This example below fetches the code
                # from the remote repository and will put it in the `src`
                # directory
                - default: basic
                  path: git/fetch
                  args: # specify URI for repository to clone
                    - 'https://example.com/code.git'
                - default: basic
                  path: prereqs
                  args: # specify phase for prereqs selection
                    - build
                - default: basic
                  path: perl/build
                - default: basic
                  path: install/with-dibsignore
                  args:
                    - build    # src from src_dir, dst to /cache/app

        bundle:

            # again, start over almost from scratch here, but you can prepare
            # base image with some tooling inside and spare some time
            from: 'alpine:3.6'

            # final containers are eventually dropped unless dibs is told to
            # keep them. This is what is done here so that we will have the
            # final image available
            keep: true # or yes, or whatever is true for YAML

            # when `keep` is set, it's also necessary to set the entry point
            # and the cmd for the final container image, so that its usage can
            # be automated easily.
            entrypoint:
                - /procfilerun
            cmd: []

            # by default, retained images are named after the `name` set at
            # the highest level of the dibs.yml file, with a tag that
            # represents the build (timestamp and pseudo-random number). You
            # can also tag the image with additional tags or name:tags.
            tags: # additional tags or name:tag
                - latest
                - 7
                - 'whatever:7'

            dibspacks:
                - default: basic
                  path: procfile
                - default: basic
                  path: prereqs
                  args:
                    - bundle
                - default: basic
                  path: install/plain-copy
                  args:
                    - path_cache: '/app'  # default is src_dir
                    - '/app'              # this is the default

    # list of steps to take, in order. Names of the steps MUST be set as
    # keys in the `definitions` associative array above
    steps:
        - build
        - bundle


### Top level: `defaults`

There are two sub-keys supported in `defaults`:

- `dibspack`: sets group of default configurations associated to a name that
  can be eventually used inside a dibspack. Example:

      defaults:
        dibspack:
          basic: # real git repository
            type:   git
            origin: https://github.com/polettix/dibspack-basic.git

      # ... then later...
      definitions:
        whateverstep:
          dibspacks:
            - default: basic
              path: prereqs
              # ... and everything else needed

    The example is the same as just writing:

      definitions:
        whateverstep:
          dibspacks:
            - type:   git
              origin: https://github.com/polettix/dibspack-basic.git
              path: prereqs
              # ... and everything else needed

    with the difference that you can reuse the defaults in `basic` over and
    over.

- `env` sets environment variables that apply to all definitions; these are
  free to override them with different values anyway. More details below in
  the specific section.


### Top level: `definitions`

This section is where definitions for the different steps can be found. It is
an associative array where the keys represent names/identifiers of the steps;
they are also what is expected to be used inside the `steps` section. So, for
example, the following is a valid structure:

    definitions:
      foo: # ...
      bar: # ...
      baz: # ...
    steps:
      - foo
      - baz
      - bar
      - baz

but the following is not because step `foo` used in `steps` is not defined:

    definitions:
      bar: # ...
      baz: # ...
    steps:
      - foo # ERROR! this is not in definitions
      - baz
      - bar
      - baz

Each definition is itself an associative array with some reference keys that
are recognized:

- `cmd`: the default command set in the final image. See [Docker][]
  documentation on [CMD][] for details. This is useful only when `keep` is set
  to a true value, otherwise its effects are ignored.

- `dibspacks`: a list of dibspacks that have to be applied in sequence. See
  below for the details.

- `entrypoint`: the default entry point set in the final image. See [Docker][]
  documentation on [ENTRYPOINT][] for details. This is useful only when `keep`
  is set to a true value, otherwise its effects are ignored.

- `from`: the starting image from where the first container is run. It might
  be a very basic image (e.g. `alpine:3.6` or so) or an image that was
  previously crafted with some basic tooling inside.

- `keep`: boolean value, set to true to keep the final container as an image.
  This is typically what is needed to save an image at the end of a `bundle`
  sequence.

- `name`: the name to associate to generated images. This overrides the `name`
  parameter at the top level and can be useful to put multiple alternative
  definitions inside the same `dibs.yml` file, e.g. to build base images. This
  is useful only when `keep` is set to a true value, otherwise it is ignored.

- `step`: the name of the step (it can e.g. be retrieved in `args` by setting
  an associative array like `type: step_name`). By default it is the same as
  the identifier of the definition.

- `tags`: additional tags for the generated image. This is useful only when
  `keep` is set to a true value, otherwise it is ignored.


The `dibspacks` list, as anticipated, is a sequence of pointers to dibspacks,
each of which is either a plain string or an associative array with the
following basic structure:

- `args`: a list of additional arguments to pass when invoking the dibspack
  program. These can either be plain *scalars* (strings, numbers, ...) or
  associative arrays as described below;

- `default`: names a key inside the `defaults.dibspack` section of the
  `dibs.yml` file where default options can be taken.

- `env`: sets step-wide environment variables. Environment variables handling
  is detailed in a section below.

- `indent`: boolean value detailing if the output from the dibspack should be
  indented or not. By default it is assumed that the dibspack does not care
  about indenting its output for pretty-printing with arrows etc. and this is
  done by `dibs`.

- `name`: name of the dibspack for reference in the logs. Defaults to
  something taken from the definition.

- `type`: the type of the dibspack, see subsections below for the different
  types available.

Depending on the `type`, the dibspack definition might contain additional
fields, explained in the sub-sections below.

The string-based definition of a dibspack is a shorthand that is recognised as
follows:

- if it's a URL that can be consumed by git, the type is assumed to be `git`
  and th definition is considered the `origin`. See below for the details on
  the `git` type.
- otherwise, it MUST have the form `<type>:<definition>` (e.g. `project:foo`).
  The `type` and the `definition` are separated and the right handler is
  called to interpret the `definition`, which is type-dependent.

#### Providing `args` to a dibspack

The arguments passed to a dibspack during invocation are:

    program src_dir cache_dir env_dir [other args..]

The *other args* can be set using the `args` key in the associative array
defining the dibspack. This points to a list of elements, that can be either
plain scalars (e.g. strings or numbers), passed verbatim, or associative
array allowing you to retrieve some data from `dibs`.

If you're just looking for a few examples, the following should all work:

    args:
      - path_cache: perl    # referred to cache
      - path_src: /prereqs  # referred to src, even with initial /
      - path_env: /some
      - path_dibspacks: build
      - path:               # same as above
          cache: perl
      - type: path          # ditto
        cache: perl
      - type: step_id       # key of step in definitions
      - type: step_name     # "step" field in definition, defaults to key

The *full* way of setting a special parameter is like this:

    args:
      - type: some_type
        this: that
        another: argument

The `type` key is used to understand what kind of functionality to call, each
having its own specific parameters. As a shorthand, the example above can be
also expressed like follows:

    args:
      - some_type:
          this: that
          another: argument

This form can come handy if the specific functionality only needs a scalar
value as argument, because you can call it like this:

    args:
      - some_type: scalar-argument

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


#### Dibspack Type `git`

In this case, the dibspack can be retrieved from a git repository. The
following keys are recognised:

- `origin`: the origin of the git repository. It can optionally have a
  *fragment* part, i.e. a hash sign `#` followed by text, that is interpreted
  as the ref to use (defaults to `master`). If the fragment part is present,
  it's an error to specify a `ref`. Examples:

      # just the origin position, defaults to master branch unless ref
      # says differently
      https://example.com/repo.git

      # set both the origin and the ref ("v42"). It's an error to also specify
      # ref explicitly in this case
      https://example.com/repo.git#v42

      # set the origin to a local directory, and the ref too
      /path/to/some/local/repo.git#devel


- `ref`: the ref to checkout. It's possible to set a branch or pin a specific
  hash/tag for better tracking and reproducibility.

- `path`: set the path inside the git repo where the dibspack can be found.  A
  git repository might contain multiple dibspack, each in a sub-path; in this
  case, this parameter allows selecting the right one. See an example in
  [dibspack-basic][]. Defaults to `operate`.

The string-based definition of the dibspack sets the parameter `origin` above.

#### Dibspack Type `inside`

This type allows specifying that the dibspack can be found inside the docker
image. It might be that the docker image is already equipped with it, or that
another dibspack put it previously.

In the associative array definition, only the `path` key is supported,
pointing to the dibspack; the path should be absolute and referred to the
filesystem inside the container.

In the string-based definition, the `path` is set, e.g.:

    inside:/path/to/dibspack

#### Dibspack Type `project`

This type indicates that the dibspack can be found inside the `dibspacks`
sub-directory of the project (which is mounted and make available inside the
container).

In the associative array definition, only the `path` key is supported,
pointing to the dibspack; the path is relative to the `dibspacks`
sub-directory of the main project directory.

In the string-based definition, the `path` is set, e.g.:

    project:path/to/dibspack

Note: dibspacks of type `git` are placed inside the `dibspacks/git`
sub-directory of the main project directory. To avoid conflicts, it's suggestd
to avoid placing additional dibspacks there, e.g. by placing all dibspacks
inside `dibspacks/local` or similar.

#### Dibspack Type `src`

This type indicates that the dibspack can be found inside the `src`
sub-directory of the project, which is also mounted in the container and whose
position is passed to the dibspack as the second positional argument. This
allows to bind the dibspacks directly with the source code, granting stricter
control over what is used for the build/bundle processes (at the expense of
loose coupling of course).

In the associative array definition, only the `path` key is supported,
pointing to the dibspack; the path is relative to the `src` sub-directory of
the main project directory.

In the string-based definition, the `path` is set, e.g.:

    src:path/to/dibspack

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
