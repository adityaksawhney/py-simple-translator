# IBM Model 2 alignment trainer for statistical machine translator
# Author: Aditya Sawhney

import collections
import codecs
import os
import sys
import cPickle

# default value handling for alignments
cdef double getAlignmentProbability(dict a, key):
  ePos, fPos, eLen, fLen = key
  if (key not in a):
    a[key] = 1.0/(fLen + 1.0)
  return a[key]

# NOTE: t must first be restructured by decoder.optimizeTranslationDict()
# Returns alignment vector
def calculateAlignment(english, french, t, a):
  alignment = []
  for i in range(len(english)):
    bestPos = -1
    best = 0.001 # chance for null alignment
    for j in range(len(french)):

      temp = (t[french[j]].get(english[i]) or 0.00001) * getAlignmentProbability(a, (i, j, len(english), len(french)))
      if temp > best:
        bestPos = j
        best = temp
    alignment.append(bestPos)
  return alignment

def alignCorpus(sentencePairs, t, a):
  alignedCorpus = []
  i = 0
  for sentencePair in sentencePairs:
    alignedCorpus.append((sentencePair, calculateAlignment(sentencePair[0], sentencePair[1], t, a)))
    i += 1
    if i % 3000 == 0:
      print str(i) + " / " + str(len(sentencePairs)) + " aligned"
  return alignedCorpus

def train(sentences, int iterations):

  def minimum():
    return 0.0001

  frenchWords = set()
  for (english, french) in sentences:
    for word in french:
      frenchWords.add(word)

  def uniformValue():
    return 1.0/float(len(frenchWords))

  t = collections.defaultdict(uniformValue) # translation 
  a = dict() # alignment

  cdef int i, j, k, eLen, fLen
  cdef double temp
  # cdef dict countt, totalt, counta, totala, totalsentence
  for q in range(iterations):
    countt = collections.defaultdict(minimum)
    totalt = collections.defaultdict(minimum)
    counta = collections.defaultdict(minimum)
    totala = collections.defaultdict(minimum)
    totalsentence = collections.defaultdict(minimum)

    for i in range(len(sentences)):
      english = sentences[i][0]
      french  = sentences[i][1]
      eLen = len(english)
      fLen = len(french)

      for j in range(eLen):
        totalsentence[english[j]] = 0.0 # Make sure we only count once per sentence per unique english word
        for k in range(fLen):
          totalsentence[english[j]] += t[(english[j], french[k])] * getAlignmentProbability(a, (j, k, eLen, fLen))
      for j in range(eLen):
        for k in range(fLen):
          temp = t[(english[j], french[k])] * getAlignmentProbability(a, (j, k, eLen, fLen)) / totalsentence[english[j]]
          countt[(english[j], french[k])] += temp
          totalt[french[k]] += temp
          counta[(j, k, eLen, fLen)] += temp
          totala[(j, eLen, fLen)] += temp

    for (english, french) in countt.keys():
      t[(english, french)] = countt[(english, french)] / totalt[french]

    for (j, k, eLen, fLen) in counta.keys():
      a[(j, k, eLen, fLen)] = counta[(j, k, eLen, fLen)] / totala[(j, eLen, fLen)]

  return (t, a)

def processDirectory(directoryName, numFiles):
  englishSentences = []
  frenchSentences  = []
  filesProcessed = 0;
  if os.path.isdir(directoryName):
    for file in os.listdir(directoryName):
      if file.endswith(".e"):
        file = file[:-2]
        sentences = processInputFiles(directoryName + "/" + file)
        englishSentences.extend(sentences[0])
        frenchSentences.extend(sentences[1])
        filesProcessed += 1
        if filesProcessed >= numFiles:
          break
  return (englishSentences, frenchSentences)

def processInputFiles(fileName):
  print(fileName)
  english = open(fileName + ".e")
  french = codecs.open(fileName + ".f", 'r', 'iso-8859-1')

  englishSentences = english.read().split("\n")
  frenchSentences  = french.read().encode('latin1').split("\n")

  englishList = []
  frenchList = []

  for i in range(min(len(englishSentences), len(frenchSentences))):
    englishSentences[i] = englishSentences[i].split()
    if len(englishSentences[i]) > 0:
      if (englishSentences[i][0] == "<s"):
          del englishSentences[i][1] # Remove snum tag
      for token in englishSentences[i]:
        if (token == "<s" or token == "</s>"):
          englishSentences[i].remove(token)
    frenchSentences[i] = frenchSentences[i].split()
    if len(frenchSentences[i]) > 0:
      if (frenchSentences[i][0] == "<s"):
            del frenchSentences[i][1] # Remove snum tag
      for token in frenchSentences[i]:
        if (token == "<s" or token == "</s>"):
          frenchSentences[i].remove(token)
    englishSentences[i] = [x.lower() for x in englishSentences[i]]
    frenchSentences[i]  = [x.lower() for x in frenchSentences[i]]
    englishList.append(englishSentences[i])
    frenchList.append(frenchSentences[i])

  return (englishList, frenchList)

def loadProbabilities():
  t = cPickle.load(open("savet.p", "rb"))
  a = cPickle.load(open("savea.p", "rb"))
  return t, a

def toyProblem(t, a):
  fr = "bon , je suis au parc".split()
  en = "i am at the park".split()
  print calculateAlignment(en, fr, t, a)

def main(loadFile, numFiles):
  if loadFile:
    t, a = loadProbabilities()
  else:
    # text = [("This is a house", "Das ist ein Haus"), ("Where is the house", "Wo ist das Haus"), ("What is a flower", "Was ist eine Blume")]
    # sentences = [(e.split(), f.split()) for (e, f) in text]
    print("Loading " + str(numFiles) + " files")
    sentences = processDirectory("../data4/training", numFiles)
    print("Loaded sentences")
    sentences = zip(sentences[0], sentences[1])
    t, a = train(sentences, 50)
    # print(a)
    cPickle.dump(dict(t), open("savet.p", "wb"))
    cPickle.dump(a, open("savea.p", "wb"))
  for (e, f) in t.keys():
    if t[(e, f)] > 0.8:
      print(e + " " + f + "\n")

if __name__ == "__main__":
  load = False
  numFiles = 1
  if len(sys.argv) > 1:
    if sys.argv[1] == "--load":
      load = True
      numFiles = 0
    else:
      numFiles = int(sys.argv[1])
  main(load, numFiles)

