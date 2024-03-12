# container

This package defines the `godot-infra` build container used to compile Godot and export projects.

## **Example usage**

### **Compiling a Godot export template**

TODO

### **Exporting a Godot project**

TODO

## **Development**

### **Setup**

The following instructions outline how to get the project set up for local development:

1. Manually run the `package-macos-sdk.yml` workflow and place the packaged `macOS` SDK into the `thirdparty/osxcross/tarballs` directory.
2. Manually run the `package-moltenvk-sdk.yaml` workflow and extract the packaged `MoltenVK` SDK into `thirdparty/moltenvk`.
3. Run the `container/build.sh` script from the repository root:

    ```sh
    LLVM_VERSION=17 \
    MACOS_VERSION=14 \
    MACOS_VERSION_MINIMUM=10.13 \
    OSXCROSS_SDK=darwin23 \
    ./container/build.sh \
        --base "docker.io/library/ubuntu:mantic"
    ```
