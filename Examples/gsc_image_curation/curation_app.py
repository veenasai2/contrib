#!/usr/bin/env python3
import docker
import os.path
from os import path
import subprocess
import sys

def get_docker_image(docker_socket, image_name):
    try:
        docker_image = docker_socket.images.get(image_name)
        return docker_image
    except (docker.errors.ImageNotFound, docker.errors.APIError):
        return None

def pull_docker_image(docker_socket, image_name):
    try:
        docker_image = docker_socket.images.pull(image_name)
        return 0
    except (docker.errors.ImageNotFound, docker.errors.APIError):
        print(f'Error: Could not fetch `{image_name}` image from dockerhub')
        print(f'Please check the image name is correct and try again.')
        return -1

def check_image_creation_success(docker_socket, image_name, log_file):
    image = get_docker_image(docker_socket, image_name)
    if image is None:
        print(f'\n\n\n`{image_name}` creation failed, exiting....')
        print(f'You can look at the logs file here: {log_file}\n\n')
        sys.exit(1)

def correct_usage_message(arg):
    print(f'\nUsage: {arg} <redis/redis:7.0.0> (for custom image)')
    print(f'Usage: {arg} <redis/redis:7.0.0> test (for test image)')
    print(f'\nUsage: {arg} -d <redis/redis:7.0.0> (for custom image with debug logs)')
    print(f'Usage: {arg} -d <redis/redis:7.0.0> test (for test image with debug logs)')


    sys.exit(1)


def main(argv):
    if len(argv) < 2:
        correct_usage_message(argv[0])

    gsc_image_with_debug='false'
    index_for_base_image_in_argv = 1
    index_for_test_flag_in_argv = 2
    # min length of argv is the length of argv without test flag
    min_length_of_argv = 2

    # Checking if debug flag is specified by the user
    if argv[1] == '-d':
       gsc_image_with_debug='true'
       index_for_base_image_in_argv+=1
       index_for_test_flag_in_argv+=1
       min_length_of_argv+=1

    # Acquiring Base image type and name from user input
    base_image_input=argv[index_for_base_image_in_argv]
    if '/' in base_image_input:
        base_image_type=base_image_input.split('/', maxsplit=1)[0]
        base_image_name=base_image_input.split('/', maxsplit=1)[1]
        if base_image_type is '' or  base_image_name is '':
            print(f'\nIncorrect format: {base_image_input}', file=sys.stderr)
            correct_usage_message(argv[0])
    else:
         print(f'\nIncorrect format: {base_image_input}', file=sys.stderr)
         correct_usage_message(argv[0])

    print(f'\n################################# Welcome to GSC Image Curation Script ##############'
            '###################\n\n')
    print(f'Note: Current version of this script tested for redis and pytorch only\n')

    gsc_app_image='gsc-{}x'.format(base_image_name)

    docker_socket = docker.from_env()
    base_image = get_docker_image(docker_socket, base_image_name)
    if base_image is None:
        print(f'Warning: Cannot find application image `{base_image_name}` locally.\n')
        print(f'Fetching from Docker Hub ...\n')
        if pull_docker_image(docker_socket, base_image_name) == -1:
            sys.exit(1)

    args=''
    log_file=base_image_type+'/'+base_image_name+'.log'
    log_file_pointer = open(log_file, 'w')

    # Generating Test Image
    if len(argv) > min_length_of_argv:
        if argv[index_for_test_flag_in_argv]:
    #        args=''
    #        log_file=base_image_name+'.log'
    #        log_file_pointer = open(log_file, 'w')
            subprocess.call(["./curation_script.sh", base_image_type, base_image_name, "test-key",
                args, "test-image", gsc_image_with_debug],stdout=log_file_pointer)
            check_image_creation_success(docker_socket,gsc_app_image,log_file)
            print(f'\n\nYou can run the {gsc_app_image} using the below command')
            print(f'docker run  --device=/dev/sgx/enclave -it {gsc_app_image}')

            return 1

    # Generating Customized image
    # Signing key
    print(f'\nDo you have a signing key (SGX requires RSA 3072 keys with public exponent equal to 3'
           '.)?')
    print(f'You can generate signing key using this command: openssl genrsa -3 -out enclave-key.pem'
           ' 3072')
    print(f'Please provide path to your signing key here: (press ENTER in case of no key)')
    print(f'Note: If you press ENTER here , then the script will autogenerate a test key using the'
           ' above command')
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
    debug_enclave_command_for_verifier=''
    if key_path == "test-key":
        debug_enclave_command_for_verifier='-e RA_TLS_ALLOW_DEBUG_ENCLAVE_INSECURE=1 -e RA_TLS_ALLOW_OUTDATED_TCB_INSECURE=1'

    # Runtime arguments
    print(f'\nDo you have any runtime args to provide?')
    print(f'[Note: Gramine will ignore any args specified at runtime, so please ensure you provide'
           ' that here only]')
    args_required = input(f'y/n: ')
    while args_required != 'y' and args_required !='n':
        print(f'\nYou have entered a wrong option, please type y or n only')
        args_required = input(f'y/n: ')

    if args_required == 'y':
        args =input(f'Please specify args as a string -> ')
        print(args)

    # Environment Variables
    print(f'\nDo you have any runtime environment variables to provide?')
    print(f'[Note: Gramine will ignore any env specified at runtime, so please ensure you provide'
           ' that here only]')
    env_required = input(f'y/n: ')
    while env_required != 'y' and env_required !='n':
        print(f'\nYou have entered a wrong option, please type y or n only')
        env_required = input(f'y/n: ')

    envs='dummy_env_var'
    if env_required == 'y':
        envs =input(f'Please specify a list of env variables and respective values separated by comma'
                     ' (accepted format: name="Xyz",age="20") -> ')

    # Get Attestation Input
    print(f'\nDo you require remote attestation (DCAP)(https://gramine.readthedocs.io/en/stable/'
           'attestation.html)?')
    print(f'[Note: attestation is required for gramine to process encrypted files]')
    attestation_required = input('y/n: ')
    while attestation_required != 'y' and attestation_required !='n':
        print(f'\nYou have entered a wrong option, please type y or n only')
        attestation_required = input('y/n: ')

    # Encrypted Files
    encrypted_files_required='n'
    ef_files='dummy_encrypted_files'
    if attestation_required == 'y':
        print(f'\nDo you need to provide encrytped files?')
        print(f'Please ensure the encrypted files are part of the base image dockerfile.')
        print(f'You can use this dockerfile (gsc_image_creation/pytorch/'
               'pytorch_with_encrypted_files/) as a reference to create a base image with encrypted'
               ' files.')
        print(f'To know more about encrypted files please follow this link:'
               ' https://gramine.readthedocs.io/en/stable/manifest-syntax.html#encrypted-files')
        encrypted_files_required = input(f'y/n: ')
        while encrypted_files_required != 'y' and encrypted_files_required !='n':
            print(f'\nYou have entered a wrong option, please type y or n only')
            encrypted_files_required = input(f'y/n: ')
        
        encryption_key = ''
        if encrypted_files_required == 'y':
            print(f'\nPlease provide the path to the encrypted files in the base image separated by'
                   ' a colon (:)')
            print(f'Accepted format: file1:path_relative_path/file2:file3')
            print(f'E.g., for gsc_image_creation/pytorch/pytorch_with_encrypted_files/Dockerfile'
                   ' based image, the encrypted files input would be --> ')
            print(f'classes.txt:input.jpg:alexnet-pretrained.pt:app/result.txt')
            ef_files=input(f'Your input here -> ')

            encryption_key = input(f'\nPlease provide absolute path to your encryption key -> ')

            while not path.exists(encryption_key):
                print(f'\nError: {encryption_key} file does not exist.')
                encryption_key = input(f'Please specify a correct key file with **absolute path** -> ')

    # Verifier image generation based on attestation input
    ca_cert_path='dummy_ca_path'
    if attestation_required == 'y':
       print(f'\n\n\n##### We are going to generate the verifier docker image first #####\n\n\n')

       # Getting verifier cert input from the user
       print(f'Do you have certs to provide?')
       print(f'Please get familiar with the certificate format here:'
              'https://github.com/gramineproject/contrib/tree/master/Examples/aks-attestation/ssl')
       print(f'[Note: If you press ENTER then test certificates will be generated automatically'
              'with Common Name=localhost and those must not be used in production ]')
       cert_available=input(f'type y or press ENTER ?')
       if len(cert_available) == 0:
           cert_available != 'n'
           ca_cert_path='verifier_image/ca.crt'
       else:
           while cert_available != 'y':
               print(f'\nYou have entered a wrong option, please type y or press ENTER')
               cert_available = input(f' y/ENTER ?')
       if cert_available == 'y':
           print(f'Please open another terminal window and copy the ca.crt, server.crt,'
                   'and server.key certificates to gsc_image_curation/verifier_image/ssl'
                   ' directory')
           input(f'Press any key to proceed')
           ca_cert_path='verifier_image/ssl/ca.crt'
           while not path.exists(ca_cert_path):
               print(f'\nError: {ca_cert_path} file does not exist.')
               print(f'Please copy ca.crt to gsc_image_curation/verifier_image/ssl/ directory')
               input(f'Press any key to proceed')
           server_cert_path='verifier_image/ssl/server.crt'
           while not path.exists(server_cert_path):
               print(f'\nError: {server_cert_path} file does not exist.')
               print(f'Please copy server.crt to gsc_image_curation/verifier_image/ssl/ directory')
               input(f'Press any key to proceed')
           server_key_path='verifier_image/ssl/server.key'
           while not path.exists(server_key_path):
               print(f'\nError: {server_key_path} file does not exist.')
               print(f'Please copy server.key to gsc_image_curation/verifier_image/ssl/ directory')
               input(f'Press any key to proceed')

       os.chdir('verifier_image')
       verifier_log_file='verifier-'+base_image_name+'.log'
       verifier_log_file_pointer = open(verifier_log_file, 'w')
       subprocess.call(["./verifier_helper_script.sh", cert_available],stdout=verifier_log_file_pointer)
       os.chdir('../')
       check_image_creation_success(docker_socket,'verifier_image:latest','verifier_image/'+verifier_log_file)


    subprocess.call(["./curation_script.sh", base_image_type, base_image_name, key_path, args,
                  attestation_required, ca_cert_path, env_required, envs, encrypted_files_required,
                  ef_files, gsc_image_with_debug],stdout=log_file_pointer)

    check_image_creation_success(docker_socket,gsc_app_image,log_file)
    print(f'\n\n\n#################### We are going to run the {gsc_app_image} image #############'
           '#######\n')
    print(f'Note: This image is generated for DCAP 1.11 specified in gsc/config.yaml.template\n')
    if attestation_required == 'y':
        print(f'Please ensure your remote attestation verifier is ready to accept the connection'
               ' **from this device/container**')
        print(f'\n\nYou can start the verifier using the below command\n')
        print(f'docker run  --net=host {debug_enclave_command_for_verifier} --device=/dev/sgx/enclave  -it verifier_image:latest {encryption_key}')
        print(f'\n\n\nYou can run the {gsc_app_image} using the below command\n')
        print(f'Please use the below commmand, if the verifier is running on localhost')
        print(f'docker run --net=host --device=/dev/sgx/enclave -e SECRET_PROVISION_SERVERS='\
               '\"localhost:4433\" -v /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket -it'\
               ' {gsc_app_image} ')
        print(f'\n\nIf the verifier is not running on the localhost, then use below command')
        print(f'docker run --device=/dev/sgx/enclave -e SECRET_PROVISION_SERVERS='\
               '<server-dns_name:port> -v /var/run/aesmd/aesm.socket:/var/run/aesmd/aesm.socket'\
               ' -it {gsc_app_image} ')
    else:
        print(f'\n\nYou can run the {gsc_app_image} using the below command')
        print(f'docker run  --device=/dev/sgx/enclave -it {gsc_app_image}')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))
