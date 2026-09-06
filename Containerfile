FROM debian:trixie

RUN apt-get update
RUN apt-get install --yes wget pv pigz tar git gh
ADD setup.sh ./
