# Trigram Language Model trainer
# Author: Aditya Sawhney

import collections
import copy
import codecs
import model2
import cPickle

# taken from https://www.dataquest.io/blog/python-counters/
# used for normalization
class Pmf(collections.Counter):
  """A Counter with probabilities."""

  def normalize(self):
    """Normalizes the PMF so the probabilities add to 1."""
    total = float(sum(self.values()))
    for key in self:
        self[key] /= total

  def __add__(self, other):
    """Adds two distributions.

    The result is the distribution of sums of values from the
    two distributions.

    other: Pmf

    returns: new Pmf
    """
    pmf = Pmf()
    for key1, prob1 in self.items():
        for key2, prob2 in other.items():
            pmf[key1 + key2] += prob1 * prob2
    return pmf

  def __hash__(self):
    """Returns an integer hash value."""
    return id(self)
  
  def __eq__(self, other):
    return self is other

START   = "<S>"
STOP    = "</S>"
UNKNOWN = "<UNK>"

def train(sentences):

  def defaultCounter():
    return Pmf()

  uni = Pmf()
  bi  = collections.defaultdict(defaultCounter)
  tri = collections.defaultdict(defaultCounter)

  for sentence in sentences:
    stoppedSentence = copy.deepcopy(sentence)
    stoppedSentence.insert(0, START)
    stoppedSentence.insert(0, START)
    stoppedSentence.append(STOP)

    prePreWord = stoppedSentence[0]
    preWord    = stoppedSentence[1]
    for i in range(2, len(stoppedSentence)):
      word = stoppedSentence[i]
      uni[word] = uni[word] + 1
      bi[preWord][word] = bi[preWord][word] + 1
      tri[(prePreWord, preWord)][word] = tri[(prePreWord, preWord)][word] + 1
      prePreWord = preWord
      preWord = word

  uni[UNKNOWN] = 1 # smoothing
  uni.normalize()
  for key in bi:
    bi[key].normalize()
  for key in tri:
    tri[key].normalize()

  return (uni, bi, tri)

def scoreTrigram(params, prePreWord, preWord, word):
  uni, bi, tri = params
  lambda1 = 0.7
  lambda2 = 0.2

  trigramProb = tri[(prePreWord, preWord)][word]
  bigramProb  = bi[preWord][word]
  unigramProb = uni[word]
  if unigramProb == 0:
    unigramProb = uni[UNKNOWN]
  return lambda1 * trigramProb + lambda2 * bigramProb + (1.0 - lambda1 - lambda2) * unigramProb

def scoreSentence(params, sentence):
  stoppedSentence = copy.deepcopy(sentence)
  stoppedSentence.insert(0, START)
  stoppedSentence.insert(0, START)
  stoppedSentence.append(STOP)
  prob = 1.0
  prePreWord = stoppedSentence[0]
  preWord    = stoppedSentence[1]
  for i in range(2, len(stoppedSentence)):
    word = stoppedSentence[i]
    prob *= scoreTrigram(params, prePreWord, preWord, word)
    prePreWord = preWord
    preWord    = word
  return prob

def processInputFiles(fileName):
  english = open(fileName + ".e")
  french = codecs.open(fileName + ".f", 'r', 'iso-8859-1')

  englishSentences = english.read().split("\n")
  frenchSentences  = french.read().encode('latin1').split("\n")

  sentences = []

  for i in range(len(englishSentences)):
    englishSentences[i] = englishSentences[i].split()
    if len(englishSentences[i]) == 0:
      continue
    if (englishSentences[i][0] == "<s"):
        englishSentences[i].remove(englishSentences[i][1])  # Remove snum tag
    for token in englishSentences[i]:
      if (token == "<s" or token == "</s>"):
        englishSentences[i].remove(token)
    for j in range(len(englishSentences[i])):
      englishSentences[i][j] = englishSentences[i][j].lower()

    sentences.append(englishSentences[i])

  return sentences

def main():
  # text = ["This is a house", "Where is the house", "What is a flower"]
  # sentences = [e.split() for e in text]
  sentences = model2.processDirectory("../data4/training/", 100)
  params = train(sentences[0])
  print(str(scoreSentence(params, "this is a test".split())))

if __name__ == "__main__":
  main()

