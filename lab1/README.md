# Lab 1

Instructions for this section will be provided in class and on Blackboard when we reach it.

Put your work for Lab 1 in this folder.


File 1: lab1/scripts/create-security-group.sh
This script addes SSH access and detials.
First it gets the IP of the machine/User.
Then it makes a secuiry group named acs730-week1-sg
Then it applies it to the EC2 instance.
Finally it echos ssh allowed from {my_IP}


File 2: lab1/scripts/create-instance.sh

Makes a EC2 Instance and profile


File 3: lab1/scripts/delete-instance.sh

deletes the instance which was made previously  (clean up)

File 4: lab1/scripts/delete-security-group.sh

Clean up for the security group made.


Experiments:


Experiment 3: Idempotent-ish Deletes


prediction: Running delete-instance.sh a second time will print "Nothing to delete." instead of throwing an AWS error
Observation: The script printed `Nothing to delete.`

Experiment 5: .gitignore
prediction: Running touch key.pem the git status will show untracked file due to gitignore file:
Observation: git status returned working tree clean. git ignore automated safety net to prevent sensitive data from leaking
