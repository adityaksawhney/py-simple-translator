# Scorer for machine translations
# Author: Aditya

from collections import Counter
import os
import codecs
import math

def getNGrams(sentence, order):
  prevWords = []
  if (len(sentence) < order):
    return Counter(prevWords)
  for i in range(0, order - 1):
    prevWords.append(sentence[i])
  ngrams = []
  for i in range(order - 1, len(sentence)):
    prevWords.append(sentence[i])
    ngramString = " ";
    ngramString = ngramString.join(prevWords)
    ngrams.append(ngramString)
    del prevWords[0]
  counts = Counter(ngrams)
  return counts

def bleuScoreSentenceOrder(guess, reference, order):
  nGramsGuess = getNGrams(guess, order)
  nGramsRef   = getNGrams(reference, order)

  divisor = len(guess) - order + 1.0
  if divisor <= 0:
    return 0.0
  ngramPrecision = 0.0
  for nGram in nGramsGuess:
    ngramPrecision += min(nGramsGuess[nGram], nGramsRef[nGram])
  ngramPrecision /= divisor

  # print(guess, reference)
  # print ngramPrecision
  return ngramPrecision

def bleuScoreSentence(guess, reference, order):
  scores = []
  for i in range(int(order)):
    scores.append(bleuScoreSentenceOrder(guess, reference, i+1))
  sum = 0.0
  for i in range(int(order)):
    sum += scores[i]
  return sum / order

def bleuScore(translationPairs):
  scores = []
  q = 0.0
  order = 4.0
  for guess, reference in translationPairs:
    score = bleuScoreSentence(guess, reference, order)
    if score <= 0:
      score = 1.0 / ((2.0 ** q) * ((len(guess) - order) or 1.0 )) # Smoothing
      q += 1.0
    scores.append(score)
    if len(scores) % 30 == 0:
      print("BLEU Scored " + str(len(scores)) + "/" + str(len(translationPairs)))
  totalScore = scores[0]
  for score in scores[1:]:
    print totalScore
    if score > 0:
      totalScore += score
    else:
      print score
  totalScore = totalScore * (1.0 / len(scores))
  return totalScore

def processDirectory(directoryName, numFiles):
  englishSentences = []
  frenchSentences  = []
  filesProcessed = 0
  if os.path.isdir(directoryName):
    for file in reversed(os.listdir(directoryName)):
      if file.endswith(".e"):
        file = file[:-2]
        sentences = processInputFiles(directoryName + "/" + file)
        englishSentences.extend(sentences[0])
        frenchSentences.extend(sentences[1])
        filesProcessed += 1
        if filesProcessed >= numFiles:
          break
  return zip(frenchSentences, englishSentences)

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

def loadTestSentences():
  sentences = processDirectory("../data4/training", 1)
  return sentences[:100]

def loadGoogleTranslated():
  file = open('./googletranslated.e')
  sentences = file.read().split("\n")
  sentences = [sentence.split() for sentence in sentences]
  sentences = [[word.lower() for word in sentence] for sentence in sentences]
  return sentences

def scoreTranslator(translate):
  testSentences = loadTestSentences() # [(source, reference), ...]
  translationPairs = []
  i = 0
  for source, reference in testSentences:
    translationPairs.append((translate(source), reference))
    i += 1
    if i%10 == 0:
      print "translated " + str(i) + "/" + str(len(testSentences))
  return bleuScore(translationPairs)

def scoreGoogleTranslate():
  googletranslated = loadGoogleTranslated()
  testSentences = loadTestSentences()
  translationPairs = []
  if len(googletranslated) != len(testSentences):
    print "Lengths are different. Continuing anyway, but the data might be wrong."
  for i in range(min(len(testSentences), len(googletranslated))):
    translationPairs.append((googletranslated[i], testSentences[i][1]))
  return bleuScore(translationPairs)

def main():
  text = ["This is a house", "Where is the house", "What is a flower"]
  guesses = ["This is a the house", "Where is house", "Who is a flower"]
  sentences = [[e.split(), f.split()] for e, f in zip(guesses, text)]
  print(sentences)
  print(bleuScore(sentences))

if __name__ == "__main__":
  main()