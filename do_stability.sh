#!/bin/bash

## TODO: 
# 


### Do the weekly stability analysis. Assumes you have Docker Desktop installed. ###

## Setup stuff:
#Requires an input directory called something like "Stability_date"
if [ $# -eq 0 ]; then
  echo "Error: No input file provided"
  echo "Usage: $0 <relative path to stability input directory>"
  exit 1
fi
subid=$1

# Set the stability scan directory (assume it's ~/stability)
stabdir=~/stability

#set the input directory (assumes it's in ~/stability/)
pardir=${stabdir}/${subid}

#start docker in the background (not sure it's capable of not popping up a window)
open -g /Applications/Docker.app

#Docker pull request. If the image is not downloaded, it'll do so now. Otherwise it'll 
#  pull any updates
docker pull diffdocker/fbirnqa:1.11.14   

## Update gradient coil temps
cd $stabdir
csv_file="GradientCoilTemps.csv"
#today's date
today=$(date +"%m/%d/%y")
#read in last line for default temps
last_line=$(tail -n 1 "$csv_file")
#internal file separator
IFS=',' read -r _ last_start last_epi1 last_epi2 last_epi3 <<< "$last_line"
#trim leading spaces
last_start=$(echo "$last_start" | xargs)
last_epi1=$(echo "$last_epi1" | xargs)
last_epi2=$(echo "$last_epi2" | xargs)
last_epi3=$(echo "$last_epi3" | xargs)

#prompt for new values using last week's values as defaults
read -p "GC4 Temp Start [$last_start]: " start
read -p "GC4 Temp Post-EPI1 [$last_epi1]: " epi1
read -p "GC4 Temp Post-EPI2 [$last_epi2]: " epi2
read -p "GC4 Temp Post-EPI3 [$last_epi3]: " epi3

#use defaults if you hit 'enter'
start=${start:-$last_start}
epi1=${epi1:-$last_epi1}
epi2=${epi2:-$last_epi2}
epi3=${epi3:-$last_epi3}

#append new line to csv
echo "$today, $start, $epi1, $epi2, $epi3" >> $csv_file

## Pull dicoms from Orthanc
orthanc_ids=$(curl -s -X POST http://localhost:8042/tools/find \
  -H "Content-Type: application/json" \
  -d "{
    \"Level\": \"Patient\",
    \"Query\": {
      \"PatientName\": \"${subid}\"
    }
  }")
orthanc_ids_clean=$(echo "$orthanc_ids" | tr -d '[ " ]')
#should only be one study
study_id=$(curl -s http://localhost:8042/patients/${orthanc_ids_clean}/studies | jq -r '.[].ID')

#download as zip
echo ""
echo "Downloading study ID $study_id to $stabdir/$subid.zip"

curl -s \
  "http://localhost:8042/studies/$study_id/archive" \
  -o "$stabdir/$subid.zip"

#unzip it
unzip $subid.zip && rm $subid.zip
#rename to take out extra subid
mv "$subid $subid" "$subid"


## Run stability evaluations with docker files.
## Updated 7/21/26 to work with Orthanc output format

#cd into the "subject" level directory, rename the default Horos dicom folder name w/o spaces
cd $pardir
if [ -d "ACTIVE KIRWAN" ]; then
    mv "ACTIVE KIRWAN" dicoms
fi

#rename folders to take out spaces and the "MR" prefix Orthanc added
find "dicoms" -depth -type d -name "MR *" -exec bash -c 'mv "$1" "$(dirname "$1")/$(basename "$1" | sed "s/^MR //")"' _ {} \; 

cd dicoms

#loop over the acquisition runs for the [20, 32, and 64] channel coils
for i in ses*; do 

  #set the input directory to the dicom directory
  indir=${pardir}/dicoms/${i}

  echo $indir
  
  #Run the docker image on the latest stability scans
  docker run -it \
    -v ${indir}/:/input/ \
    -v ${pardir}:/fbirn_out/ \
    docker.io/diffdocker/fbirnqa:1.11.14 \
    /input/ \
    /fbirn_out/$i
    
  ##install weasyprint (if it's not already)
  #pip install weasyprint
  #convert output to pdf
  /opt/homebrew/Cellar/weasyprint/63.1/libexec/bin/weasyprint ${pardir}/${i}/index.html ${pardir}/${i}.pdf
  
  #pull out summary statistics
  for metric in "meanGhost" "SNR" "SFNR"; do
    value=$(grep "observation name=\"$metric\"" "${pardir}/${i}/summaryQA.xml" | sed -n "s/.*<observation name=\"$metric\" type=\"float\">\([^<]*\)<\/observation>.*/\1/p")
    echo "$value" > "${pardir}/${i}/${metric}.txt"
  done

  #meanGhost=`cat ${pardir}/${i}/summaryQA.xml | grep "observation name=\"meanGhost\"" | sed -n 's/.*<observation name="meanGhost" type="float">\([^<]*\)<\/observation>.*/\1/p'`
  #echo $meanGhost > ${pardir}/${i}/meanGhost.txt
  
done

#clean up
cd $pardir
rm -r ${pardir}/dicoms

#pull values to plot change over time using R
Rscript ${stabdir}/do_graph_stability.R

#show the results
#open ${stabdir}/Summary.html
osascript -e 'tell application "Safari" to activate' \
    -e 'tell application "Safari" to make new document with properties {URL: "file:///Users/mriuser/stability/Summary.html"}' \
    -e 'tell application "Safari" to set bounds of front window to {0, 0, 1200, 1200}'

#update the output on readthedocs via github

git remote add origin git@github.com:MindCORE-MRI/stability-scanning.git

git pull origin main

git add .
git commit -m "Auto update from stability script"
git push -u origin main


