# acl2015
Codes for the experiment of ACL2015 short paper

## Environment Setting

Clone the repository, and open the "scripts/config.sh" file, edit the environment paths for you environment. (GIZA to your giza installed directory, TRAVATAR for travatar, etc...)

## Corpus Preparation
Download Europarl corpus source file from:

    http://www.statmt.org/europarl/v7/europarl.tgz

and extract it, then you get "txt" directory that contains all the proceedings in each language.

In the same directory that you can see this "txt" directory, execute:

    $ ~/acl2015/europarl-extractor/europarl-extractor/multi-sentence-align-corpus.perl en de es fr it

then you can get aligned proceedings with XML tags:

    aligned/en-de-es-fr-it/*
    
Now you can merge all the proceeedings without XML tags by executing:

    $ ~/acl2015/europarl-extractor/merge.py aligned/en-de-es-fr-it data/ en de es fr it

then you can get line aligned corpus:

    data/en-de-es-fr-it.* .

## Training Language Model

You can train language model by executing (e.g. English, train set size 100k):

    $ ~/acl2015/scripts/train-lm.sh en path/to/train.en 100000

## Training SCFG Models

You can train SCFG translation model by executing (e.g French to English, train set size 100k, dev/test set size 1.5k, including preprocessing, tuning, testing steps):

    $ ~/acl2015/scripts/train.sh hiero fr en path/to/corpus.{fr,en} path/to/blm.en 100000 1500

## Pivot Translation

You can triangulate 2 SCFG TM into MSCFG TM (proposed method) by executing (e.g. fe-en * en-de => fr-de, including tuning, testing steps):

    $ ~/acl2015/scripts/pivot.sh hiero_fr-en hiero_en-de hiero_fr-de/corpus --method=prodprob --lexmethod=prodweight --nbest=20 --multitarget

You can triangulate 2 SCFG TM into 1 SCFG TM (baseline method) by executing:

    $ ~/acl2015/scripts/pivot.sh hiero_fr-en hiero_en-de hiero_fr-de/corpus --method=prodprob --lexmethod=prodweight --nbest=20

You can also cascade 2 SCFG TM and get the output by executing:

    $ ~/acl2015/scripts/cascade.sh hiero_fr-en hiero_en-de hiero_fr-de/corpus/test.{fr,de}

## Contact

If you find any issues, please contact Akiva Miura:

 * akiva.miura [at] gmail.com
 * @akivajp on Twitter
