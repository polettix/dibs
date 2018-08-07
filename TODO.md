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
