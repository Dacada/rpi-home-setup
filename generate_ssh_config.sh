ansible localhost -i 'localhost,' -c local -m ansible.builtin.template -a "src=ssh_config dest=ssh_config.generated mode=0600" -e @ansible/vars/secrets.yml --ask-vault-pass
