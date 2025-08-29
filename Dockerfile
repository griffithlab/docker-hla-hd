FROM mgibio/immuno_tools-cwl:1.0.2

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip vim bowtie2 build-essential unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


WORKDIR /opt
# Give directories/files sane default perms on copy
COPY --chmod=0755 hlahd /opt/hlahd

# --- Unzip any dictionary zips into /opt/hlahd/dictionary_3.55 (keep the zip files) ---
RUN for z in /opt/hlahd/dictionary_3.55/*.zip; do \
      if [ -e "$z" ]; then unzip -o "$z" -d /opt/hlahd/dictionary_3.55; fi; \
    done

WORKDIR /opt/hlahd
# Build helper binaries and dictionary indexes
RUN bash install.sh

# Ensure all dirs are 755 and files are 755 (world-readable/executable),
# and strip CRLF from any shell scripts.
RUN find /opt/hlahd -type d -exec chmod 0755 {} + && \
    find /opt/hlahd -type f -exec chmod 0644 {} + && \
    find /opt/hlahd/bin -type f -exec chmod 0755 {} + && \
    find /opt/hlahd -type f -name "*.sh" -exec sed -i 's/\r$//' {} +

# Your wrapper
COPY --chmod=0755 hlahd_script_wdl.sh /usr/bin/hlahd_script_wdl.sh
RUN sed -i 's/\r$//' /usr/bin/hlahd_script_wdl.sh

# Put HLA-HD tools first on PATH
ENV PATH="/opt/hlahd/bin:/opt/hlahd:${PATH}"

CMD ["/bin/bash"]
