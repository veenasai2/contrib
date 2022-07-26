#!/usr/bin/env python3
import os.path
from os import path
import subprocess
import sys


def main(argv):
    if len(argv) < 2:
        print(f'Usage: {argv[0]} <redis/redis:7.0.0> (for custom image)', file=sys.stderr)
        print(f'Usage: {argv[0]} <redis/redis:7.0.0> test (for test image)', file=sys.stderr)
        return 1
    print(f'\n################################# Welcome to GSC Image Curation Script #################################\n\n')
    print(f'Note: Current version of this script tested for redis and pytorch only\n')
    # Acquiring Base image type and name from user input
    base_image_type=argv[1].split('/', maxsplit=1)[0]
    base_image_name=argv[1].split('/', maxsplit=1)[1]

    # Generating Test Image
    if len(argv) == 3:
        if argv[2].startswith('test'):
            args_test='./curation_script_for_test_image.sh' + ' ' + base_image_type + ' ' + base_image_name
            print(args_test)
            subprocess.call(args_test, shell=True)
            return 1

    # Generating Customized image
    # Signing key
    print(f'\nDo you have a signing key (SGX requires RSA 3072 keys with public exponent equal to 3.)?')
    print(f'You can generate signing key using this command: openssl genrsa -3 -out enclave-key.pem 3072')
    print(f'Please provide path to your signing key here: (press ENTER in case of no key)')
    print(f'Note: If you press ENTER here , then the script will autogenerate a test key using the above command')
    key_path = input(f'Key file name along with absolute path in .pem format -> ')

    if(len(key_path) == 0):
        key_path = "test-key"
    else:
        while not path.exists(key_path):
            print(f'\nError: {key_path} file does not exist.')
            key_path = input(f'Please specify a correct key file with **absolute path** -> ')
            if(len(key_path) == 0):
                key_path="test-key"
                break
    # Get Attestation Input
    print(f'\nDo you require remote attestation (DCAP)(https://gramine.readthedocs.io/en/stable/attestation.html)?')
    print(f'[Note: attestation is required for gramine to process encrypted files]')
    attestation_required = input('y/n: ')
    while attestation_required != 'y' and attestation_required !='n':
        print(f'\nYou have entered a wrong option, please type y or n only')
        attestation_required = input('y/n: ')

    # Verifier image generation based on attestation input
    ca_cert_path='dummy_ca_path'
    if attestation_required == 'y':
       print(f'\n\n\n##### We are going to generate the verifier docker image first #####\n\n\n')

       os.chdir('verifier_image')
       args_verifier ='./verifier_helper_script.sh'
       subprocess.call(args_verifier, shell=True)
       os.chdir('../')

       print(f'\n\nPlease specify path to your verifier ca certificate (crt format only)')
       ca_cert_path=input(f'Suggestions : verifier_image/ca.crt  -> ')
       while not path.exists(ca_cert_path):
           print(f'Error: {ca_cert_path} file does not exist.')
           ca_cert_path=input(f'Please specify a correct ca certificate file with **absolute path** (crt format only) -> ')
           print(f'You have given the following ca cert path: {ca_cert_path}')


    # Environment Variables
    print(f'\nDo you have any runtime environment variables to provide?')
    print(f'[Note: Gramine will ignore any env specified at runtime, so please ensure you provide that here only]')
    env_required = input(f'y/n: ')
    while env_required != 'y' and env_required !='n':
        print(f'\nYou have entered a wrong option, please type y or n only')
        env_required = input(f'y/n: ')

    envs='dummy_env_var'
    if env_required == 'y':
        envs =input(f'Please specify a list of env variables and respective values separated by comma'
                       '(accepted format: name="Xyz",age="20") -> ')

    # Encrypted Files
    encrypted_files_required='n'
    ef_files='dummy_encrypted_files'
    if attestation_required == 'y':
        print(f'\nDo you need to provide encrytped files?')
        print(f'Please ensure the encrypted files are part of the base image dockerfile.')
        print(f'You can use this dockerfile (gsc_image_creation/pytorch/pytorch_with_encrypted_files/)'
                  ' as a reference to create a base image with encrypted files.')
        print(f'To know more about encrypted files please follow this link:'
                  ' https://gramine.readthedocs.io/en/stable/manifest-syntax.html#encrypted-files')
        encrypted_files_required = input(f'y/n: ')
        while encrypted_files_required != 'y' and encrypted_files_required !='n':
            print(f'\nYou have entered a wrong option, please type y or n only')
            encrypted_files_required = input(f'y/n: ')

        if encrypted_files_required == 'y':
            print(f'\nPlease provide the path to the encrypted files in the base image separated by a colon (:)')
            print(f'Accepted format: file1:path_relative_path/file2:file3')
            print(f'E.g., for gsc_image_creation/pytorch/pytorch_with_encrypted_files/Dockerfile based image,'
                      'the encrypted files input would be --> ')
            print(f'classes.txt:input.jpg:alexnet-pretrained.pt:app/result.txt')
            ef_files=input(f'Your input here -> ')

    args ='./curation_script.sh' + ' ' + base_image_type + ' ' + base_image_name + ' ' + key_path + ' ' + attestation_required + ' ' + ca_cert_path + ' ' + env_required + ' ' + envs + ' ' + encrypted_files_required + ' ' + ef_files

    subprocess.call(args, shell=True)
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
