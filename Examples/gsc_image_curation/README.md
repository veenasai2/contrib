# GSC Image Curation Script

Here, we will put some details about the script.

## Prerequisites

```sh
$ sudo apt-get install jq

$ sudo apt-get install docker.io python3 python3-pip

$ pip3 install docker jinja2 toml pyyaml
```

## User can view these pre-curated Gramine Confidential Compute Images

### Gramine curated app's Redis:7.0.0 Confidential Compute Image

```sh
$ docker pull veenacontainerregistry.azurecr.io/gsc-redis-image_700_preview

$ docker run  --device=/dev/sgx/enclave -it veenacontainerregistry.azurecr.io/gsc-redis-image_700_preview
```

### Gramine curated app's Pytorch Confidential Compute Image

Please refer `gsc_image_curation/pytorch/pytorch_with_plain_text_files` to see the contents of this image

```sh
$ docker pull veenacontainerregistry.azurecr.io/gsc-pytorch-image

$ docker run  --device=/dev/sgx/enclave -it veenacontainerregistry.azurecr.io/gsc-pytorch-image
```
