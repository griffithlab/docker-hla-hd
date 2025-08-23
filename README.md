# docker-hla-hd
Dockerfile, dictionary and scripts needed to run hla-hd


Git LFS is used to save big files: Fasta/dictionary 
# 1) Install Git LFS once on the machine
git lfs install

# 2) Clone the repo as usual
git clone git@github.com:griffithlab/docker-hla-hd.git
cd docker-hla-hd

# 3) Pull down the large files stored in LFS
git lfs pull
