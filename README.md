This is meant to be a very light & simple example of a native extension for duckdb.

The [extension-template](https://github.com/duckdb/extension-template) is great, but it's a lot of files to track and my usecase is generally much simpler:

- build some simple 1-off extension in C++ that does some specific thing (import weird data)
- build and & load it with `-unsigned`
- wrap the whole thing in a docker container, so I can have a ready-made duckdb CLI that can use it
- publish that docker on Github registry so I can use ti without having to build anything

I don't want long build-time, and a lot of build-deps, and tracking a bunch of files I didn't make in my repo, so I reuse [releases](https://github.com/duckdb/duckdb/releases) as much as possible.

## usage

```sh
# build (downloads deps on first run, fast rebuilds after)
cmake -G Ninja -B build
cmake --build build

# test it, on host
duckdb -unsigned
# LOAD 'build/quack.duckdb_extension';
# SELECT quack('world');

# build a docker container
docker build -t duckdb-quack .

# run the docker container
docker run -v ./data:/data -it --rm duckdb-quack mydb.duckdb
```

## customization

Edit `CMakeLists.txt` to change:

- **DUCKDB_VERSION** — which duckdb release to target (default: `v1.5.0`)
- **EXTENSION_NAME** — output extension name (default: `quack`)
- **EXTENSION_SOURCES** — your `.cpp` files

Edit `Dockerfile` to change the `DUCKDB_VERSION` build arg.

To target a different duckdb version:

```sh
cmake -G Ninja -B build -DDUCKDB_VERSION=v1.5.0
```

## auto-publish

This automatically publishes on `ghcr.io` using whatever the name is, so for example, you can run this with this command:

```sh
docker run -v ./data:/data -it --rm ghcr.io/konsumer/duckdb-extension-lite:latest
# SELECT quack('world');
```

If you don't want that, you can delete/modify the [workflow](.github/workflows/docker.yml).
