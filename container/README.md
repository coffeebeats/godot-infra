# container

This package defines the `godot-infra` build container used to compile Godot and export projects.

## **Example usage**

### **Compiling a Godot export template**

To build Godot export templates with the `godot-infra` container, run the command below:

```sh
docker run \
    -v $PWD/dist:/home/ubuntu/godot-infra/dist:Z \
    -v $PWD/.scons:/home/ubuntu/godot-infra/.scons:Z \
    -v $PWD/example:/home/ubuntu/godot-infra/project:ro,Z \
    $([[ -d "$GDENV_HOME" ]] && echo "-v $(realpath $GDENV_HOME):/home/ubuntu/godot-infra/.gdenv:Z") \
    $([[ -d "$GDBUILD_HOME" ]] && echo "-v $(realpath $GDBUILD_HOME):/home/ubuntu/godot-infra/.gdbuild:Z") \
    -e SCONS_CACHE=/home/ubuntu/godot-infra/.scons \
    -e SCRIPT_AES256_ENCRYPTION_KEY=<ENCRYPTION_KEY> \
    localhost/godot-infra:latest gdbuild template \
        --verbose \
        --out /home/ubuntu/godot-infra/dist \
        --project /home/ubuntu/godot-infra/project \
        --release \
        <PLATFORM>
```

### **Exporting a Godot project**

TODO

## **Development**

### **Setup**

The following instructions outline how to get the project set up for local development:

1. Manually run the `package-macos-sdk.yml` workflow and place the packaged `macOS` SDK into the `thirdparty/osxcross/tarballs` directory.
2. Manually run the `package-moltenvk-sdk.yaml` workflow and extract the packaged `MoltenVK` SDK into `thirdparty/moltenvk`.
3. Run the `container/build.sh` script from the repository root:

    ```sh
    LLVM_VERSION=17 \                                                                                                                                                                                      10:59:38 AM
    MACOS_VERSION=14 \
    MACOS_VERSION_MINIMUM=10.13 \
    OSXCROSS_SDK=darwin23 \
    GDENV_VERSION= \
    GDPACK_VERSION= \
    GDBUILD_VERSION= \
    ./container/build.sh \
        --base "docker.io/library/ubuntu:mantic"
    ```
