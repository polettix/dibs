# TO-DO

- run from docker container

- rename ENVIRON to something more meaningful?

- check dibspacks from src still work

- add "dockerfile" execution

- add fetching stuff from tar file

- switch to bigger YAML module, supporting more features OK

- simplify refactoring of Dibs OK

- add "detect" to run whole step REMOVED COMPLETELY

- use cached dibspack (within same session) - WONTDO caching is too
  aggressive eventually

- check how to avoid envs in Docker image
   - will have to save stuff inside env/ and import that optionally,
     otherwise there's no way to really remove a var


## Use Cases

### Straight to the point

Source directory is the base. Ideally, when you check out a fresh copy of
the repository, you just type a command and it does what it takes.

Caching should work as expected after the first run.

Solution:

- run in root of source tree
- explicit option `--local|-l`
- project directory location still available through `-p|--project-dir`
  BUT it defaults to directory `.dibs` inside current directory
- it contains the `cache`, `dibspacks` and `env` sub-directories. The
  `src` directory might either be a link pointing back to `..` or just be
  adapted according to the conditions
- `dibs.yml` file first searched in current (root) directory, then inside
  the project directory
