name: CI

on:
  pull_request:
  push:
    branches-ignore: [__PROD_BRANCH__, __DEV_BRANCH__]   # these two run the tests as the first step of their deploy workflow
  workflow_call:

jobs:
  test:
    runs-on: ubuntu-latest
__CI_STRATEGY__
    steps:
      - uses: actions/checkout@v4
__CI_STEPS__
