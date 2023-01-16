import json
import re
from subprocess import check_output

inventoryString = """{
    "local": {
        "hosts": {
            "localhost": {
            }
        },
        "vars": {
            "ansible_connection": "local",
            "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        }
    },
    "all": {
        "children": {
            "local": null,
            "windows": null
        }
    },
    "windows": {
        "vars": {
            "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
            "ansible_user": "oliver heinemann",
            "ansible_password": "Maren2019!",
            "ansible_shell_type": "cmd",
            "ansible_connection": "ssh"
        }
    }
}"""
inventory = json.loads(inventoryString)

hosts = check_output("arp -a", shell=True).decode("utf-8").split("\n")

if len(hosts) > 0:
    for host in hosts:
        if host != "":
            mac = re.search("([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}", host).group()
            ip = re.search("([0-9]{1,3}\.?){4}", host).group()
            if not "hosts" in inventory["windows"]:
                inventory["windows"]["hosts"] = {}
            inventory["windows"]["hosts"]["windows_host"] = {"ansible_host": ip, "mac": mac}

with open("inventory.json", "w") as f:
    json.dump(inventory, f)
