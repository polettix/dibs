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

These programs will be executed inside containers. The resulting container
might then be used as a base for further dibspacks executions and also for
saving a final image (or more).

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

- anything that starts with `project:` is a path resolved relatively to the
  `dibspacks` sub-directory in the project directory

- anything that starts with `src:` is a path resolved inside the `src`
  directory in the project, which is also the reference directory where the
  source code is (i.e. dibspacks that fetch your code should put it there)

- anything else generates an exception!

Dibspacks taken from `git` are saved inside the `dibspacks/git` directory.
Although it's not mandatory, it's probably better to put *local* dibspacks
inside another sub-directory, e.g. `dibspacks/local` or so.

The execution of the programs in a dibspack is as follows:

- first of all the `detect` program is executed
- if the execution is successful (exit code `0`), the `operate` program is
  executed.

Both programs are invokes like this:

    <program> <step-name> <src> <cache> <env>

Example:

    detect build /tmp/src /tmp/cache /tmp/env

The `step-name` is of course the name of the step. This allows you to define a
buildpack that supports multiple steps in one single place.

The last three arguments are paths to the associated directories in the
project directory, but "seen" from inside the container. In particular:

- `src` and `cache are available in read-only mode for `detect` and in
  read-write mode for `operate`
- `env` is always set read-only.

The directories are usually mounted under `/tmp` like in the example, so you
should avoid using them otherwise. This might change in the future.
Additionally, the `dibspacks` directory is mounted too as `/tmp/dibspacks`,
read-only; you should not use this directory directly, unless you know what
you are doing and accept that this may change in the future.

## Configuration

The configuration is kept, by default, inside YAML file `dibs.yml`. The
generic structure at the higher level is like this:

    ---
    name: your-project-name
    env:
        THIS
        THAT: 'whatever you want'
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
            # ...
        bundle:
            from: some-image:tag
            dibspacks:
                - https://example.com/prereqs#v42
                - https://example.com/bundler#v72
                - project:bundle
                - https://example.com/runner#v37
            keep: 1
            entrypoint:
                - /runner
            cmd: []
            tags:
                - latest
            # ...

Notes on the top-level keys:

- `name` is the name of the project. It is also used as the default for
  creating and naming images along the line, although you can override it in
  any of the `definitions`
- `env` sets some environment variables before executing all dibspacks
  programs (they can be overridden by definition-specific `env` values). If
  just the name is provided, the value is taken from the environment where
  `dibs` is run, otherwise the specific value is set
- `steps` define a sequence of steps to take. Each step MUST have a
  definition inside section `definitions`
- `definitions` is a key-value mapping between possible `steps` and their
  contents.

Definitions are where you can... define what should be done in a step. It
supports the following keys:

- `from` is the base image of the container for the step. 
- `dibspacks` is a list of locations for dibspacks, as explained in the
  previous section.
- `keep`, when present and set to a true value will make `dibs` keep the image
  at the end of the execution of the step. It MUST be a valid YAML boolean
  value, or null (interpreted as false), or absent (interpreted as false).
- `entrypoint` and `cmd` are set to the corresponding features of the
  generated Docker image
- `tags` allow setting additional tags (the generated image always takes the
  *name* and an automatically generated tag related to date and time)
- `env` allows overriding the main `env` values or setting new ones
- `name` allows overriding the globally set `name` to generate images with a
  different name for a step.


## Running

When you run `dibs`, by default it uses the current directory as the project
directory and looks for `dibs.yml` inside. It then executes all the `steps` in
order:

- for each step, the associated dibspacks are detected
- in the step, the dibspacks are executed as a sequence of containers:
    - the first one is started based on the image set with `from`
    - the following ones from the freezing of the previous container
- after each step, if the associated definition has `keep` set, the container
  image is kept and additional `tags` are added, otherwise it is dropped.

This allows implementing this kind of workflow:

- define one or more *build* phases that leverage images/dibspacks that
  include build tools, like a compiler;
- save the outcome of that/those phases in the `cache` directory
- define a *bundle* phase where that outcome is fit inside a *release* image
  that only contains the needed tools for running (but does not include
  building tools)

