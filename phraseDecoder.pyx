# Set of decoders to translate sentences from french to english using a phrase table.
# Author: Aditya Sawhney

import model2
import collections
import trigramlangmodel
import bisect
import math

def simpleDecode(sentence, phraseTable):
  translation = []
  i = 0
  while i < len(sentence):
    j = len(sentence)
    while (not (" ".join(sentence[i:j]) in phraseTable)) and j > i:
      j -= 1
    if j == i:
      translation.append(sentence[j])
      i += 1
    else:
      frenchKey = " ".join(sentence[i:j])
      translation.extend(max(phraseTable[frenchKey].keys(), key=(lambda k: phraseTable[frenchKey][k])).split(" "))
      i = j
  return translation

def getSimpleTranslator(phraseTable):
  def translate(sentence):
    return simpleDecode(sentence, phraseTable)
  return translate

# Simple decoder but with language model also
def simpleDecodeWithLangModel(sentence, phraseTable, trigramScorer, params):
  translation = ["<S>", "<S>"]
  i = 0
  while i < len(sentence):
    j = len(sentence)
    while (not (" ".join(sentence[i:j]) in phraseTable)) and j > i:
      j -= 1
    if j == i:
      translation.append(sentence[j])
      i += 1
    else:
      frenchKey = " ".join(sentence[i:j])
      translation.extend(max(phraseTable[frenchKey].keys(), key=lambda k: phraseTable[frenchKey][k] * trigramScorer(params, translation[-2], translation[-1], k.split(" ")[0]) * (trigramScorer(params, translation[-1], k.split(" ")[0], k.split(" ")[1]) if (len(k.split(" ")) > 1) else 1 )).split(" "))
      i = j
  return translation[2:]

def getSimpleDecoderWithLangModel(phraseTable, trigramScorer, params):
  def translate(sentence):
    return simpleDecodeWithLangModel(sentence, phraseTable, trigramScorer, params)
  return translate

def bestBreakdown(phrase, phraseTable, lookupDict=None):
  if lookupDict is None:
    lookupDict = {}
  best = 0.0
  bestTranslation = ""
  phraseString = " ".join(phrase)
  if phraseString in phraseTable:
    best = max(phraseTable[phraseString].values())
    bestTranslation = max(phraseTable[phraseString].keys(), key=(lambda k: phraseTable[phraseString][k]))
  for i in range(1, len(phrase) - 1):
    temp1 = bestBreakdown(phrase[:i], phraseTable, lookupDict)
    temp2 = bestBreakdown(phrase[i:], phraseTable, lookupDict)
    temp3 = temp1[0] * temp2[0]
    if temp3 > best:
      best = temp3
      bestTranslation = " ".join([temp1[1], temp2[1]])

  return (best, bestTranslation)

def getStackTranslator(phraseTable, trigramScorer, params):
  def translate(sentence):
    return stackDecode(sentence, phraseTable, trigramScorer, params)
  return translate

def stackDecode(source, phraseTable, trigramScorer, params):
  futureCosts = [] # Store future cost values to cut down calculation time

  def calculateFutureCosts(source, phraseTable, params):
    uni, bi, tri = params
    for word in source:
      score = 1.0
      if word in phraseTable:
        bestcase = max(phraseTable[word].values())
        if bestcase > 0:
          score *= bestcase
          # print "translation"
        # print score
      if uni[word]:
        score *= uni[word]
        # print "found"
      else:
        score *= uni["<UNK>"]
      # print(score)
      futureCosts.append(score)
    return

  def getFutureCost(remaining):
    cost = 1.0
    for i in remaining:
      cost *= futureCosts[i]
    return cost

  calculateFutureCosts(source, phraseTable, params)
  stackSize = 20
  stacks = [[] for i in range(len(source) + 1)]
  stacks[0].append((0, getFutureCost(tuple(range(len(source))))))  # start with stack size 0, entry of null hypothesis with just future cost.
  # hypotheses = [[]] # start with just the empty hypothesis
  # Tuple of remaining indices
  remainings = [tuple(range(len(source)))] # at index i, remaining i.
  remainingDict = {
    tuple(range(len(source))): 0
  }
  #  (PrevPrev, prev, remainings, end index): stateIndex
  states     = [("<S>", "<S>", 0, 0)] # at index i, state i.
  stateDict  = {
    ("<S>", "<S>", 0, 0): 0
  }
  previousStates = [-1] # At position i, the index of the state preceding state i
  phrasePieces   = [""]

  def getStateIndex(state):
    if not state in stateDict:
      stateIndex = len(states)
      states.append(state)
      stateDict[state] = stateIndex
      previousStates.append(0)
      phrasePieces.append("")
    return stateDict[state]

  def getRemainingIndex(remaining):
    if not remaining in remainingDict:
      remainingIndex = len(remainings)
      remainings.append(remaining)
      remainingDict[remaining] = remainingIndex
    return remainingDict[remaining]

  def addEntryToStack(entry, stack, lastState, phrase):
    for oldEntry in stacks[stack]:
      if oldEntry[0] == entry[0]:
        if oldEntry[1] < entry[1]:
          del oldEntry
          # bisect.insort(stacks[stack], entry)
          stacks[stack].insert(0, entry)
          previousStates[entry[0]] = lastState
          phrasePieces[entry[0]] = phrase
        return
    else:
      # bisect.insort(stacks[stack], entry)
      stacks[stack].insert(0, entry)
      previousStates[entry[0]] = lastState
      phrasePieces[entry[0]] = phrase

  def getStackIndex(remaining):
    # Get stack number
    # print len(source), len(remaining)
    return len(source) - len(remaining)

  # def calculateDistortion(i, j):
  #   math.exp()

  def calculateNewScore(oldState, newPhrase, oldScore, sourceRange):
    newPhraseList = newPhrase.split(" ")
    score = trigramScorer(params, oldState[0], oldState[1], newPhraseList[0]) * oldScore * (trigramScorer(params, oldState[1], newPhraseList[0], newPhraseList[1]) if (len(newPhraseList) > 1) else 1)
    for i in range(sourceRange[0], sourceRange[1]):
      score = score / futureCosts[i]
    score = score * phraseTable[" ".join(source[sourceRange[0]:sourceRange[1]])][newPhrase] # Translation probability
    # targetIndex = len(remainings[oldState[2]])
    diff = abs(oldState[3] - sourceRange[0])
    score = score / math.exp(diff)
    # score = score * getAlignmentProbability(a, (targetIndex, sourceIndex, len(source), len(source))) # Alignment Probability. Note that this is not sophisticated enough to handle different length translations yet
    return score

  # create a new entry with the new state, new hypothesis, and new score. Add to appropriate stack and merge with appropriate entries.
  def addPhrase(entry, phrase, sourceRange):
    # print entry, word, sourceIndex
    oldStateIndex, score = entry
    oldState = states[oldStateIndex]
    remainingsIndex = oldState[2]
    remaining = list(remainings[remainingsIndex])
    for i in range(sourceRange[0], sourceRange[1]):
      remaining.remove(i)
    remaining = tuple(remaining)
    newState = (oldState[1], phrase, getRemainingIndex(remaining), sourceRange[1])
    newScore = calculateNewScore(oldState, phrase, entry[1], sourceRange)
    entry = (getStateIndex(newState), newScore)
    stackIndex = getStackIndex(remaining)
    addEntryToStack(entry, stackIndex, oldStateIndex, phrase)
    return

  def pruneStackByCount(stack):
    stacks[stack].sort(key=lambda k: k[1], reverse=True) # Only necessary if we don't sort on insertion
    stacks[stack] = stacks[stack][:stackSize]
    return

  def getPotentialPhrasesWithSourceIndices(state):
    potentials = []
    remaining = remainings[state[2]]
    for i in range(len(remaining)):
      translationFound = False
      j = 0
      while i + j < len(remaining):
        if remaining[i + j] != remaining[i] + j:
          break
        fPhrase = " ".join(source[remaining[i]:remaining[i + j] + 1])
        for phrase in sorted(phraseTable[fPhrase], key=lambda k: phraseTable[fPhrase][k])[-10:]:
          potentials.append((phrase, (remaining[i], remaining[i + j] + 1)))
          translationFound = True
        if not translationFound and i == j:
          potentials.append((source[remaining[i]], (remaining[i], remaining[i] + 1)))
        j += 1

    return potentials

  def traceBackHypothesis(endStateIndex):
    hypothesis = ""
    stateIndex = endStateIndex
    while not (previousStates[stateIndex] == -1):
      # hypothesis.append((states[stateIndex][1], remainings[states[stateIndex][2]]))
      hypothesis = " ".join([phrasePieces[stateIndex], hypothesis])
      stateIndex = previousStates[stateIndex]
    return hypothesis[:-1]

  # cdef int i
  for i in range(1, len(source) + 1):
    pruneStackByCount(i-1)
    for entry in stacks[i-1]:
      # print entry
      state = states[entry[0]]
      potentials = getPotentialPhrasesWithSourceIndices(state);
      # (word, sourceIndex)
      for potential in potentials:
        addPhrase(entry, potential[0], potential[1])
      

  # print stacks
  finalList = stacks[len(source)]
  best = finalList[0]
  endState = best[0]
  bestHypothesis = traceBackHypothesis(endState)

  return bestHypothesis

def getAlignmentProbability(a, key):
  ePos, fPos, eLen, fLen = key
  if (key not in a):
    a[key] = 1.0/(fLen + 1.0)
  return a[key]

def scoreTranslation(translation, t, a, langScorer, params):
  french, english, alignment = translation

  def getAlignmentScore(a, alignment, eLen, fLen):
    score = 1
    for q in range(eLen):
      score *= getAlignmentProbability(a, (i, alignment[i], eLen, fLen))
    return score
  
  # cdef int i, j
  # cdef double score = 1.0
  
  for i in range(len(english)):
    score *= t[english[i]][french[alignment[i]]] # Translation

  score *= langScorer(params) # Language Model
  score *= getAlignmentScore(a, alignment, len(english), len(french)) # Alignment 

  return score

def main():
  t, a = model2.loadProbabilities()
  print t
  print simpleDecode("this is a law", t, a)

if __name__ == "__main__":
  main()

