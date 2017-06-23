#!/bin/bash
rsync -avz --progress --exclude=logs --exclude=.git . aliyun:~/yunbi-prd