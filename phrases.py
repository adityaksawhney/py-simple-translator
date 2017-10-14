# Training system to use aligned corpus to calculate a phrase table
# Author: Aditya Sawhney

import collections
import model2

def defaultValue():
  return 0.0

def phraseDictionary():
  return collections.defaultdict(defaultValue)

def trainPhrases(alignedCorpus):
  phraseCounts = collections.defaultdict(phraseDictionary)

  i = 0
  for sentencePair, alignment in alignedCorpus:
    extractPhraseCountsToDict(sentencePair, alignment, phraseCounts)
    i += 1
    if i % 10000 == 0:
      print "extracted " + str(i) + " / " + str(len(alignedCorpus))

  return phraseCounts

def prune(phraseCounts, threshold, quotient):
  threshold = float(threshold)
  for key in phraseCounts.keys():
    if sum(phraseCounts[key].values()) < threshold:
      del phraseCounts[key]

  quotient = float(quotient)
  for key in phraseCounts.keys():
    threshold = float(max(phraseCounts[key].values())) / quotient
    for ekey in phraseCounts[key].keys():
      if phraseCounts[key][ekey] < threshold:
        del phraseCounts[key][ekey]

  return phraseCounts

def normalize(phraseCounts):
  for key in phraseCounts:
    total = float(sum(phraseCounts[key].values()))
    for translatedKey in phraseCounts[key]:
      phraseCounts[key][translatedKey] /= total
  return phraseCounts

def extractPhraseCountsToDict(sentencePair, alignment, phraseCounts):
  english = sentencePair[0]
  french  = sentencePair[1]

  phrasePairs = getPhrasePairIndices(alignment)

  for phrasePair in phrasePairs:
    engPhrase = " ".join(english[phrasePair[0][0]: phrasePair[0][1] + 1])
    frPhrase  = " ".join(french[phrasePair[1][0]: phrasePair[1][1] + 1])
    phraseCounts[frPhrase][engPhrase] += 1.0

  return phraseCounts

# Takes an alignment and returns the indices of corresponding phrases.
def getPhrasePairIndices(alignment):
  phrasePairs = []

  for i in range(len(alignment)):
    sourceRange = (i, i)
    targetRange = (alignment[i], alignment[i])
    for j in range(i, len(alignment)):
      if targetRange[0] == -1:
        if j + 1 < len(alignment):
          targetRange = (alignment[j + 1], alignment[j + 1])
        continue;
      sourceRange = (i, j)
      if alignment[j] < targetRange[0] and alignment[j] > -1:
        targetRange = (alignment[j], targetRange[1])
      elif alignment[j] > targetRange[1]:
        targetRange = (targetRange[0], alignment[j])
      # Check to see if this range is a valid phrase (there can be no extras overlapping)
      for q in range(sourceRange[0]):
        if alignment[q] >= targetRange[0] and alignment[q] <= targetRange[1]:
          break
      else:
        for q in range(sourceRange[1] + 1, len(alignment)):
          if alignment[q] >= targetRange[0] and alignment[q] <= targetRange[1]:
            break
        else:
          phrasePairs.append((sourceRange, targetRange))

  return phrasePairs

def main():

  alignment = [0, 1, 1, 4, 6, 8, 7]
  print getPhrasePairIndices(alignment)

if __name__ == "__main__":
  main()