# Dockerfile for walledclaude. Installs all the tools Claude Code likes to rely on, plus some development tools you may require for common projects. Refine the installed software to your liking. This controls the size of the image.

FROM node:20-slim

ARG CLAUDE_VERSION
LABEL claude-code.version="${CLAUDE_VERSION}"

# packages obtained from Claude web interface environment 
# (by asking Claude about it ;)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git less procps ripgrep jq unzip \
    build-essential pkg-config \
    python3 python3-pip python3-venv \
    poppler-utils qpdf ghostscript tesseract-ocr \
    imagemagick pandoc graphviz \
    fonts-dejavu fonts-liberation \
    libopenblas0 \
    && rm -rf /var/lib/apt/lists/*
    # latex would be useful, but very large (multiple GB)
    # libreoffice (only needed for docx->pdf,pptx->pdf and ~600MB
    # libopenblas for scipy.integrate

RUN pip install --break-system-packages --no-cache-dir \
      pypdf pdfplumber pdfminer.six pikepdf pypdfium2 pdf2image img2pdf reportlab \
      python-docx python-pptx openpyxl markitdown \
      pandas numpy scipy matplotlib pillow lxml beautifulsoup4 uv

ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
RUN uv python install 3.13

# install Julia. Adjust paths so the install is visible to the agent. Make writable to let user install packages
ENV JULIAUP_DEPOT_PATH=/opt/julia
ENV JULIA_DEPOT_PATH=/opt/julia
ENV PATH="/opt/julia/bin:${PATH}"
RUN curl -fsSL https://install.julialang.org | sh -s -- -y --path /opt/julia --add-to-path no \
      && chmod -R a+rX /opt/julia
ENV JULIA_DEPOT_PATH=/tmp/home/.julia:/opt/julia

RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_VERSION} \
      pdf-lib pdfjs-dist pptxgenjs docx marked tsx typescript

# prevents issues with host user/guest node user clashing
RUN groupmod -g 1001 node && usermod -u 1001 -g 1001 node

# some standard environment variables that cause unnecessary warnings.
ENV MPLCONFIGDIR=/tmp/home/.cache/matplotlib
ENV XDG_CACHE_HOME=/tmp/home/.cache
RUN mkdir -p ${MPLCONFIGDIR} ${XDG_CACHE_HOME} /tmp/home/.julia
# We only know the runtime uid/gid at launch, so this home dir must be writable
# by an arbitrary user. Set the sticky bit just in case. Note,
# however, that each walledclaude instance is run under the host
# uid/gid later anyways, so they may interfere with each other.
RUN find /tmp/home -type d -exec chmod 1777 {} + \
    && find /tmp/home -type f -exec chmod 0666 {} +

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
# you can supply an optional [command] to the entrypoint script
# and this way also run other agentic harnesses.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
