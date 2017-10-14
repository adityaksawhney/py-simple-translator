# Set of decoders to translate sentences from french to english using translation and alignment probabilities.
# Author: Aditya Sawhney

import model2
import collections
import trigramlangmodel
import bisect

def simpleDecode(sentence, t, a, direction):
  if type(sentence) is str:
    sentence = sentence.split()

  translation = []

  # cdef int i
  for i in range(len(sentence)):
    keys = t[sentence[i]].keys()
    if len(keys) == 0:
      translation.append(sentence[i])
    else:
      translation.append(max(keys, key=(lambda k: t[sentence[i]][k])))

  return translation

def getSimpleTranslator(t, a):
  def translate(sentence):
    return simpleDecode(sentence, t, a, 1)
  return translate

# Simple decoder but with language model also
def simpleDecodeWithLangModel(sentence, t, a, trigramScorer, params):
  translation = ["<S>", "<S>"]
  for i in range(len(sentence)):
    keys = t[sentence[i]].keys()
    if len(keys) == 0:
      translation.append(sentence[i])
    else:
      translation.append(max(keys, key=(lambda k: t[sentence[i]][k] * trigramScorer(params, translation[i], translation[i + 1], k))))
  return translation[2:]

def getSimpleDecoderWithLangModel(t, a, trigramScorer, params):
  def translate(sentence):
    return simpleDecodeWithLangModel(sentence, t, a, trigramScorer, params)
  return translate

def getStackTranslator(t, a, trigramScorer, params):
  def translate(sentence):
    return stackDecode(sentence, t, a, trigramScorer, params)
  return translate

def stackDecode(source, t, a, trigramScorer, params):
  futureCosts = [] # Store future cost values to cut down calculation time

  def calculateFutureCosts(source, t, params):
    uni, bi, tri = params
    for word in source:
      score = 1.0
      if t[word]:
        bestcase = t[word][max(t[word], key=lambda k: t[word][k])]
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

  calculateFutureCosts(source, t, params)
  stackSize = 10
  stacks = [[] for i in range(len(source) + 1)]
  stacks[0].append((0, getFutureCost(tuple(range(len(source))))))  # start with stack size 0, entry of null hypothesis with just future cost.
  # hypotheses = [[]] # start with just the empty hypothesis
  # Tuple of remaining indices
  remainings = [tuple(range(len(source)))] # at index i, remaining i.
  remainingDict = {
    tuple(range(len(source))): 0
  }
  #  (PrevPrev, prev, remainings): stateIndex
  states     = [("<S>", "<S>", 0)] # at index i, state i.
  stateDict  = {
    ("<S>", "<S>", 0): 0
  }
  previousStates = [-1] # At position i, the index of the state preceding state i

  def getStateIndex(state):
    if not state in stateDict:
      stateIndex = len(states)
      states.append(state)
      stateDict[state] = stateIndex
      previousStates.append(0)
    return stateDict[state]

  def getRemainingIndex(remaining):
    if not remaining in remainingDict:
      remainingIndex = len(remainings)
      remainings.append(remaining)
      remainingDict[remaining] = remainingIndex
    return remainingDict[remaining]

  def addEntryToStack(entry, stack, lastState):
    for oldEntry in stacks[stack]:
      if oldEntry[0] == entry[0]:
        if oldEntry[1] < entry[1]:
          del oldEntry
          # bisect.insort(stacks[stack], entry)
          stacks[stack].insert(0, entry)
          previousStates[entry[0]] = lastState
        return
    else:
      # bisect.insort(stacks[stack], entry)
      stacks[stack].insert(0, entry)
      previousStates[entry[0]] = lastState

  def getStackIndex(remaining):
    # Get stack number
    # print len(source), len(remaining)
    return len(source) - len(remaining)

  def calculateNewScore(oldState, newWord, oldScore, sourceIndex):
    score = trigramScorer(params, oldState[0], oldState[1], newWord) * oldScore
    score = score / futureCosts[sourceIndex]
    score = score * t[source[sourceIndex]][newWord] # Translation probability
    targetIndex = len(remainings[oldState[2]])
    score = score * getAlignmentProbability(a, (targetIndex, sourceIndex, len(source), len(source))) # Alignment Probability. Note that this is not sophisticated enough to handle different length translations yet
    return score

  # create a new entry with the new state, new hypothesis, and new score. Add to appropriate stack and merge with appropriate entries.
  def addWord(entry, word, sourceIndex):
    # print entry, word, sourceIndex
    oldStateIndex, score = entry
    oldState = states[oldStateIndex]
    remainingsIndex = oldState[2]
    remaining = list(remainings[remainingsIndex])
    remaining.remove(sourceIndex)
    remaining = tuple(remaining)
    newState = (oldState[1], word, getRemainingIndex(remaining))
    newScore = calculateNewScore(oldState, word, entry[1], sourceIndex)
    entry = (getStateIndex(newState), newScore)
    stackIndex = getStackIndex(remaining)
    addEntryToStack(entry, stackIndex, oldStateIndex)
    return

  def pruneStackByCount(stack):
    stacks[stack].sort(key=lambda k: k[1], reverse=True) # Only necessary if we don't sort on insertion
    stacks[stack] = stacks[stack][:stackSize]
    return

  def getPotentialWordsWithSourceIndices(state):
    potentials = []
    remaining = remainings[state[2]]
    for i in range(len(remaining)):
      translationFound = False
      for word in sorted(t[source[remaining[i]]], key=lambda k: t[source[remaining[i]]][k])[-10:]:
        potentials.append((word, remaining[i]))
        translationFound = True
      if not translationFound:
        potentials.append((source[remaining[i]], remaining[i]))

    return potentials

  def traceBackHypothesis(endStateIndex):
    hypothesis = []
    stateIndex = endStateIndex
    while not states[stateIndex][1] == "<S>":
      # hypothesis.append((states[stateIndex][1], remainings[states[stateIndex][2]]))
      hypothesis.append(states[stateIndex][1])
      stateIndex = previousStates[stateIndex]
    hypothesis.reverse()
    return hypothesis

  # cdef int i
  for i in range(1, len(source) + 1):
    for entry in stacks[i-1]:
      # print entry
      state = states[entry[0]]
      potentials = getPotentialWordsWithSourceIndices(state);
      # (word, sourceIndex)
      for potential in potentials:
        addWord(entry, potential[0], potential[1])
      pruneStackByCount(i)

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

def optimizeTranslationDict(t):
  def defaultValue():
    return 10**-6
  def default():
    return collections.defaultdict(defaultValue)
  newT = collections.defaultdict(default)
  for key in t:
    if not key[1] in newT:
      newT[key[1]] = dict()
    newT[key[1]][key[0]] = t[key]

  return newT

def main():
  t, a = model2.loadProbabilities()
  print t
  print simpleDecode("this is a law", t, a)

if __name__ == "__main__":
  main()

