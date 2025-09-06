# For artifact evaluators
Please follow the instructions below to set up connection to the setup for evaluation using the private key we provided.

# Setting up connection to the evaluation setup
Please take the private key file `pass_ae_sshkey` sent in the email.

Constrain the permission of the private key file:
```bash
chmod 400 pass_ae_sshkey
```

Connect to the evaluation setup using the following command:
```bash
ssh -i pass_ae_sshkey eurosys26ae@dock.cs.washington.edu
```
It will prompt you to enter password to `dedongx@kittitas1`. 

The password is: `eurosys26ae`, which is also the password needed for `sudo`.

Then you will be conencted to `dedongx@kittitas1`, the initiator machine for experiments.

# Running the experiments
Navigate to the artifact directory:
```bash
cd PASS_AE
```

Run the experiment script:
```bash
sudo ./run_all_experiments.sh
```

We recommendn running the experiments in a  `tmux` or `screen` session, so that the experiments can continue to run even if your connection is interrupted.

# Checking the results
After the experiments are done, you can check the results in the corresponding directory like in `PASS_AE/pass_application_benchmarks/db_bench` directory.

The results are collected in the two high-level directories:
- `pass_fio_experiments` which holds the results for fio benchmarks which serves as motivation example and microbenchmarks for our paper.
- `pass_application_benchmarks` which holds the results for application benchmarks of filebench, db_bench, and YCSB.