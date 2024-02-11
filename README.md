# Archlinux aarch64 Raspberry Pi Image Builder

## Overview

This repository contains tools and workflows for building Archlinux aarch64 images tailored for Raspberry Pi. It includes shell scripts for local building and a GitHub Actions workflow for automated building and releasing of images.

## Prerequisites

- Bash environment (for running shell scripts)
- GitHub account (for using the GitHub Actions workflow)
- Docker (optional, for containerized builds)
- Access to a Raspberry Pi model supported by the scripts

## Building Images

### Locally Using Shell Scripts

#### `build_archlinux_rpi_aarch64_img.sh`

This script automates the process of building a custom Archlinux aarch64 image for Raspberry Pi. It includes setting up environment variables, downloading necessary files, and packaging the final image.

To use the script:

```bash
./build_archlinux_rpi_aarch64_img.sh
```

Ensure you have the necessary permissions to execute the script.

#### `build_locally.sh`

For developers looking to perform the build process locally with more control over the environment variables and configurations, `build_locally.sh` provides a detailed script to manage the build process.

To execute:

```bash
./build_locally.sh
```

### Via GitHub Actions

#### `rpi_aarch64_image_builder.yml`

This GitHub Actions workflow facilitates the automated building and uploading of Archlinux aarch64 images for Raspberry Pi. It triggers on push events, builds the image using a self-hosted runner, and uploads the final image to a specified location.

To integrate the workflow:

1. Fork or clone this repository.
2. Modify the `.github/workflows/rpi_aarch64_image_builder.yml` as necessary.
3. Push the changes to your repository to trigger the workflow.

## Features

- Automated image building with GitHub Actions.
- Customizable scripts for local builds.
- Supports various Raspberry Pi models.
- Integrates with external storage solutions for image hosting.

## Customization

Modify the environment variables and parameters within the scripts and the GitHub Actions workflow to tailor the build process to your requirements. Check the comments within each file for guidance on adjustments.

## Contributing

Contributions are welcome! If you have improvements or bug fixes, please open a pull request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.