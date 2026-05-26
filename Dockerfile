FROM rocker/tidyverse:4.6.0

# Environment variables
ENV PATH="${PATH}:/usr/lib/rstudio-server/bin" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib/R/lib"

# Configure RStudio
RUN echo "session-timeout-minutes=0" >> /etc/rstudio/rsession.conf && \
    echo "session-save-action-default=no" >> /etc/rstudio/rsession.conf && \
    echo "copilot-enabled=1" >> /etc/rstudio/rsession.conf

# Set CRAN mirror globally
RUN echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' \
    >> /usr/local/lib/R/etc/Rprofile.site

# Install demo R packages
RUN Rscript -e "install.packages(c('here', 'janitor'))"
