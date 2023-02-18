
import platform
import os
import re
import subprocess
import json
import re
import uuid
from subprocess import check_output
import getpass


OS = ""
WSL = False
USER = ""
PASSWORD = ""
HOSTNAME = "localhost"

def main():
    check_os()
    print(OS + (" (WSL2)" if WSL else ""))
    make_inventory()


def get_windows():
    hosts = check_output("arp -a", shell=True).decode("utf-8").split("\n")
    if len(hosts) > 0:
        for host in hosts:
            if host != "":
                mac = re.search("([0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}", host).group()
                ip = re.search("([0-9]{1,3}\.?){4}", host).group()
                return {"ip":ip, "mac":mac}


def get_mac_address():
    mac_num = hex(uuid.getnode()).replace('0x', '').upper()
    mac = '-'.join(mac_num[i: i + 2] for i in range(0, 11, 2))
    return mac

#    result = subprocess.run(['cmd', '/c', 'C:/User/oliver.heinemann/test.bat'], stdout=subprocess.PIPE)
#    output = result.stdout.decode('utf-8')

#    print(output)

#    match = re.search(r"Physical Address.*: ([\w\d-]+)", output)
#    if match:
#        mac = match.group(1).upper()
#        print(mac)


def check_os():
    global OS, WSL
    os_name = platform.system()
    if os_name == "Windows":
        OS = "Windows"
    elif os_name == "Linux":
        OS = "Linux"
        uname_r = os.popen("uname -r").read()
        if "microsoft" in uname_r.lower():
            WSL = True
    elif os_name == "Darwin":
        OS = "macOS"
        os_version = platform.mac_ver()[0]


def make_inventory():
    global PASSWORD, USER, HOSTNAME
    inventoryString = """{
        "all": {
            "children": {}
        }
    }"""
    inventory = json.loads(inventoryString)

    mac = get_mac_address()

    print(mac)

    inventory["all"]["children"][OS] = None

    local = { OS: {
        "hosts": {
            HOSTNAME: {
                "vars": {
                    "ansible_connection": "local",
                    "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                    "mac": mac
                }
            }
        },
    }}
 
    inventory.update(local)

    if WSL == True:
        inventory.update({"windows": {
            "hosts": {
                "windows_host": {
                    "vars": {
                        "ansible_host": None,
                        "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                        "ansible_user": "",
                        "ansible_password": "",
                        "ansible_shell_type": "cmd",
                        "ansible_connection": "ssh",
                        "mac": None
                    }
                }
            },
        }})
        win = get_windows()
        print("WSL2: " + win["ip"] + " -- " + win["mac"]) 
        USER = input("Please add username of your WINDOWS HOST maschine: ")
        PASSWORD = getpass.getpass(prompt="Please add the password of your WINDOWS HOST maschine: ")
        inventory["windows"]["hosts"]["windows_host"]["vars"]["ansible_password"] = PASSWORD
        inventory["windows"]["hosts"]["windows_host"]["vars"]["ansible_user"] = USER
        inventory["windows"]["hosts"]["windows_host"]["vars"]["ansible_host"] = win["ip"]
        inventory["windows"]["hosts"]["windows_host"]["vars"]["mac"] = win["mac"]
        inventory["all"]["children"]["windows"] = None

    with open(os.path.expanduser('~') + "/.rocket-launch/ansible/inventory.json", "w") as f:
        json.dump(inventory, f)


if __name__ == "__main__":
    main()
