## A4 Discussion Log: Findings from trying an off-the-shelf tone model

## Goal:
Test an existing audEERING emotion recoginition model with 10-20 test_audio clips.
Determine if arousal, valence, and dominance values can correctly be mapped to the project's tone tags - excited, upset, calm, or none - based on the project's existing thresholds.
This will serve as the baseline for the audio section of the project.

## Initial Model Loading and Evaluation
test_audeering.py was created as an initial test script to verify that the audEERING model could be loaded successfully and produce arousal, dominance, and valence scores

This standard transforemrs pipeline produced model-weight mismatch warnings so results were not used. Further investigation showed that the checkpoint uses the Wav2Vec2ForSpeechClassification architecture which the installed Transformers version did not expose in the class directly. As a result, the model architecture was recreated using Wav2Vec2Model which allowed the checkpoint to load without missing/unexpected weight warnings and produced plausible emotion scores. This corrected implementation was incorporated into the final baseline.py

I have deleted the test_audeering.py file even because its sole purpose was as a development and sanity-check tool so it was not needed in the final A4 implementation.

## Model:
The chosen audEERING model from Hugging Face: audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim

The processor and the model are loaded by the backend when it initializes. On the first run, the required model files may need to be downloaded before running baseline.py. The model weights are not included in this repo.

Outputs:
-arousal: energy level behind the speech
-valence: how positive or negative the emotion in the speech sounds
-dominance: degree of control / authority the speaker projects

Use the arousal and valence scores  of each audio clip to assign a tone tag

## Test Data + Audio Preprocessing
Recorded test audio clips were 48 kHz in .mp3 format. However the audEERING model expected 16 kHz audio.

Thus, baseline.py does the following:
-Converts all the test_audio clips from stereo to mono
-Resamples audio from 48kHz to 16kHz
-Does not save modified audio files to the disk

Note that these 20 MP3 recordings (comprised of three differnt voices) were stored locally in ml/tone/test_audio and are excluded from Git through the repo's .gitignore. If you are reproducing the experiment, you will need to provide your own MP3 recordings inside the aforementioned folder. The recordings used for this baseline test were organized with filenames beginning with 'calm', 'excited', 'neutral', and 'upset'

## Tag mapping
The following are the project's threshold specified in docs/GRAPTION_CONTEXT.md:

-Arousal > 0.65 && valence > 0.55 --> excited
-Arousal > 0.65 && valence < 0.40 --> upset
-Arousal < 0.30 --> calm
-Otherwise --> none

However, the thresholds were modified upon testing with several different individual's audio
-Arousal > 0.64 && valence > 0.45 --> excited
-Arousal > 0.47 && valence < 0.40 --> upset
-0.38 < Arousal < 0.48 && valence > 0.45 --> calm
-Otherwise --> none

The new thresholds were maintained during this initial experiment bc goal was pure evaluation of an existing model with an existing baseline

## Initial Model Results
The model successfully processed all 28 test clips.

The model correctly produced 'excited' for 2 of the 3 excited clips and returned 'none' for the third excited clip even though human review identified clear positive energy and high-pitched tone.

All three clips intended to represent 'upset' were classified as 'none'. Human review found clear frustration, annoyance, or negativity in all three.

The calm clips were frequently classified as 'none'. Human review identified that two out of the three as clearly calm, while the third could be interpreted as either none or calm because there is slight excitement.

One none clip was classified as 'calm' even though human review identified it as neutral and monotone. The two other neutral clips were classified as 'none' which aligned with human review.

## Threshold-Tuned Model Results
After reviewing the initial model results, I adjusted the arousal and valence thresholds to be able to better distinguish calm, excited, upset, and no tones

The model correctly classified 5/8 clips as 'calm' which was a significant improvement from the initial model results. Human review identified that the three that were incorrectly classified as 'none' could be interpreted as either none or calm because there is slight excitement.

The model correctly produced 'excited' for 6 of the 8 excited clips. However, it returned 'calm' and 'upset' for the two incorrectly labeled clips even though human review identified clear positive energy and high-pitched tone.

One none clip was classified as 'calm' even though human review identified it as neutral and monotone. The three other neutral clips were classified as 'none' which aligned with human review.

The modified thresholds made a major improvement in correctly classifying the 'upset clips' - 6/8. The other 2 clips intended to represent 'upset' were classified as 'none'. Human review found clear frustration, annoyance, or negativity in all upset clips.


## Notes from Initial Human Review (before threshold changes + collection of additional audio clips)

Human review was used to determine whether the model's tags matched the perceived tone of each recording based on the predefined thresholds (no tuning yet). Filename categories were treated as intended categories.

1. calm_clip_one
    - Model Tag: none
    - Human Review: incorrect
    - Notes: Clearly calm
2. calm_clip_two
    - Model Tag: none
    - Human Review: Incorrect
    - Notes: Clearly calm
3. calm_clip_three
    - Model Tag: none
    - Human Review: Reasonable
    - Notes: Between calm and neutral; possible undertones of slightly excited
4. excited_clip_one
    - Model Tag: excited
    - Human Review: correct
    - Notes: Very excited
5. excited_clip_two:
    - Model Tag: excited
    - Human Review: correct
    - Notes: High energy and strong intonation
6. excited_clip_three:
    - Model Tag: none
    - Human Review: incorrect
    - Notes: There was high pitch and clear positive energy
7. neutral_clip_one:
    - Model Tag: calm
    - Human Review: incorrect
    - Notes: Very monotone; lacks the airy quality of a calm voice
8. neutral_clip_two:
    - Model Tag: none
    - Human Review: correct
    - Notes: Neutral with no clear emotional tone
9. neutral_clip_three:
    - Model Tag: none
    - Human Review: correct
    - Notes: Neutral with no clear emotional tone
10. upset_clip_one:
    - Model Tag: none
    - Human Review: incorrect
    - Notes: clear fustration and negativity
11. upset_clip_two:
    - Model Tag: none
    - Human review: incorrect
    - Notes: clear signs of frustration via big sigh and annoyance
12. upset_clip_three:
    - Model Tag: none
    - Human review: incorrect
    - Notes: rushed, high pitched, angry

## Findings
The initial results showed that the fixed threshold mapping does not consistently match the perceived vocal tone.

Clearest example was with 'upset': all three clips sounded upset to human review, but none reached the required arousal threshold of 0.65.

The model also confused low arousal with calmness once because the arousal score of 'neutral_clip_one' was below 0.30 and thus received a 'calm' tag even though human review identified that the voice was monotone and neutral as opposed to calm.

The model also missed calm clips because their arousal scores were above the 0.30 calm threshold.

Results suggest that arousal alone cannot accurately distinguish calm from neutral and that the current threhold combination might be too restrictive for different representations of upset/excited voices.

However, threshold tuning produced better results. In the latest 28-clip run, 20 clips were correctly classified, with 6/8 ecited clips and 6/8 upset clips correctly labeled. However, 3/8 calm clips were still misclassifeid and 1 clip intended to receive a 'none' tag was labeled as 'calm'. Thus, we can conclude that adjusting arousal and valence thresholds can improve the mapping between emotion scores and the tone tags.

## Timings
Initial Test Timings: Individual inference times were recorded (and displayed) and ranged from 0.22 to 0.57 seconds per clip, with an average of approximately 0.36 secs

New (most recent) Test Timings: Individual inference times were recorded (and displayed) and ranged from 0.30 to 0.72 seconds per clip.

## Takeaway
The audEERING model works as an off-the-shelf baseline and can produce useful emotion dimensions without training a custom model. Initial testing showed that fixed thresholds do not consistentily agree with human review across the test clips of varying emotions, thus prompting further experimentation with the tag mapping.

The tuned thresholds had pretty good preliminary results; however, with any test, more clips could improve accuracy.
As a result, the baseline should be treated as an initial comparison as opposed to the final tone classifier. Additional test and threshold tuning may be needed before using these tags within the larger project.


## A4.1 Progress: Tone Backend and Schema Updates
Project supports a custom tone model and an audEERING baseline model. These models represent emotion differently (one has 6 options while the latter only has 3 numerical scores) so they don't return the same information.

The existing schema expected 6 emotion probabilities: anger, disgust, fear, happy, neutral, and sad. However, the audEERING model returns three numerical scores: arousal, valence, and dominance and so if we kept the old model we can't accurately represent the audEERING output correctly.

## A4.1 Latest Baseline Run and Per-Clip Results
Purpose: A4.1 baseline verifies that the reusable tone backend can process a folder of audio recordings and export the audEERING model's arousal, valence, and dominance scores, predicted tone tags, and inference latency to a CSV file

## Run Configuration
- Model: audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim
- Input: 28 locally stored audio recordings featuring 3 different voices
- Audio preprocessing: Convert stereo recordings to mono and resample to 16 kHz when necessary.
- Output: ml/tone/results.csv
- Tag mapping: The tuned arousal and valence thresholds documented in the A4 findings.

Per Clip Results include:
- file name
- intended label
- arousal score
- valence score
- dominance score
- predicted tag
- latency

## Observations
- Overall: 20/28 clips correctly classified
- Calm: 5/8 correct
- Excited: 6/8 correct
- Upset: 6/8 correct
- None: 3/4 correct

- `calm_speaker0_one.mp3`: arousal=0.44277, valence=0.5856, dominance=0.54042, tag=calm, latency=615.97 ms
- `calm_speaker0_three.mp3`: arousal=0.4733, valence=0.50756, dominance=0.53512, tag=calm, latency=591.44 ms
- `calm_speaker0_two.mp3`: arousal=0.45869, valence=0.57254, dominance=0.53635, tag=calm, latency=594.74 ms
- `calm_speaker1_one.mp3`: arousal=0.41518, valence=0.43334, dominance=0.47482, tag=None, latency=571.06 ms
- `calm_speaker1_two.mp3`: arousal=0.35808, valence=0.54589, dominance=0.44394, tag=None, latency=580.81 ms
- `calm_speaker2_one.mp3`: arousal=0.3088, valence=0.44497, dominance=0.39965, tag=None, latency=602.81 ms
- `calm_speaker2_three.mp3`: arousal=0.38408, valence=0.52823, dominance=0.45989, tag=calm, latency=705.92 ms
- `calm_speaker2_two.mp3`: arousal=0.39295, valence=0.56352, dominance=0.49383, tag=calm, latency=760.07 ms
- `excited_speaker0_one.mp3`: arousal=0.81619, valence=0.81739, dominance=0.80016, tag=excited, latency=657.09 ms
- `excited_speaker0_three.mp3`: arousal=0.69894, valence=0.47741, dominance=0.67741, tag=excited, latency=542.05 ms
- `excited_speaker0_two.mp3`: arousal=0.6892, valence=0.62782, dominance=0.689, tag=excited, latency=568.57 ms
- `excited_speaker1_one.mp3`: arousal=0.47862, valence=0.4807, dominance=0.53628, tag=calm, latency=751.27 ms
- `excited_speaker1_two.mp3`: arousal=0.58893, valence=0.20495, dominance=0.62322, tag=upset, latency=692.40 ms
- `excited_speaker2_one.mp3`: arousal=0.66858, valence=0.7723, dominance=0.67938, tag=excited, latency=634.54 ms
- `excited_speaker2_three.mp3`: arousal=0.64938, valence=0.6641, dominance=0.65487, tag=excited, latency=847.48 ms
- `excited_speaker2_two.mp3`: arousal=0.70393, valence=0.66788, dominance=0.67842, tag=excited, latency=844.04 ms
- `none_speaker0_one.mp3`: arousal=0.29238, valence=0.47676, dominance=0.40588, tag=None, latency=530.15 ms
- `none_speaker0_three.mp3`: arousal=0.41863, valence=0.54257, dominance=0.50573, tag=calm, latency=451.10 ms
- `none_speaker0_two.mp3`: arousal=0.35345, valence=0.40732, dominance=0.43273, tag=None, latency=482.44 ms
- `none_speaker1_one.mp3`: arousal=0.36106, valence=0.49524, dominance=0.45163, tag=None, latency=748.29 ms
- `upset_speaker0_one.mp3`: arousal=0.61186, valence=0.21576, dominance=0.6557, tag=upset, latency=604.95 ms
- `upset_speaker0_three.mp3`: arousal=0.63486, valence=0.28663, dominance=0.66575, tag=upset, latency=717.67 ms
- `upset_speaker0_two.mp3`: arousal=0.5545, valence=0.23688, dominance=0.60208, tag=upset, latency=889.41 ms
- `upset_speaker1_one.mp3`: arousal=0.56496, valence=0.33733, dominance=0.57044, tag=upset, latency=524.23 ms
- `upset_speaker1_two.mp3`: arousal=0.47301, valence=0.29636, dominance=0.53337, tag=upset, latency=705.46 ms
- `upset_speaker2_one.mp3`: arousal=0.54898, valence=0.61797, dominance=0.58818, tag=None, latency=743.28 ms
- `upset_speaker2_three.mp3`: arousal=0.37828, valence=0.47705, dominance=0.43303, tag=None, latency=778.24 ms
- `upset_speaker2_two.mp3`: arousal=0.48402, valence=0.34614, dominance=0.53813, tag=upset, latency=605.34 ms

The tuned thresholds correctly classified 20 / 28 recordings. The model performed best on the excited, upset, and none categories with at least 75% accuracy in the same test set. two recordings that were supposed to "excited" were misclassified: one received a calm tag and the other received an upset tag. Two recordings intended to be upset received no tag, while one recording intended to be calm and one intended to be none were assigned the calm tag. We can conclude that threshold tuning can improve mapping from arousal and valence scores to protect tone tags, but the calm category is still difficult to distinguish from neutral or no-tone recordings

## Inference Latency
According to the 28 recordings, inference latency ranged from approximately 451.10 ms to 889.41 ms, with an average of approximately 655.03 ms per clip.


## A7: Tone Threshold Tuning and Evaluation

### Goal
Evaluate if the audEERING model's arousal and valence scores could reliably distinguish the project'st one tags: excited, upset, calm, and none.

Object: use data-driven threshold selection to maximize the number of recordings assigned each tone tag while attempting to maintain 80% precision. Thresholds were selected using one group of speakers and evaluated on a separate held-out group to determien whether the results generalized to unseen speakers.

Both precision and coverage were considered:
- Precision: how often a predicted tag is correct
- Coverage: the percentage of recordings assigned that tag

Goal: prioritize reliable predictions over assigning a tag to every recording. A wrogn emotion tag is worse than returning no tag.

## A5.1 Score Visualization
A5.1 test set contained 56 recordings across four intended labels: calm, excited, neutral, and upset.

ml/tone/plot_scores.py was used to visualize arousal against valence with recordings colored by their human-assigned labels and current production threshold boundaries displayed

The plot showed overlap between emotion categories, particularly between calm and neutral which suggests that fixed arousal and valence boundaries might not reliably distinguish all intended tone categories.

Plot: ml/tone/a5_1_score_plot.png

## CREMA-D Dataset
To exapdn evaluation beyond the 56 clips from A5.1, I selected 300 CREMA-D recordings.

The selected data subset contains:
- 100 recordings mapped to excited (happy).
- 100 recordings mapped to upset (anger).
- 100 recordings mapped to neutral (neutral).

The recordings were divided into two groups based on actor identity:
- Tuning set: 150 recordings
- Held-out set: 150 recordings

The split used separate actor group to reduce the possibility that the same speakers would appear in both threshold selection and evaluation. The selected recordings represented 85 unique actors.

The CREMA-D labels were mapped to the project's tone categories:
- Happy --> excited
- Anger --> upset
- Neutral --> none

## CREMA-D Score Visualization
The CREMA-D results were plotted using ml/tone/plot_scores.py

The visualization showed overlap between the three emotion categories. Excited recordings were generally more concentrated towards higher arousal and positive valence, while neutral recordings were more concentrated toward lower arousal. However, neither pattern was consistern enough to completely separate the categories. Upset was particularly spread across the arousal and valence dimensions, with some appearing in regions also occupied by excited and neutral recordings.

Plot: ml/tone/crema_d_score_plot.png

## Threshold Search Methodology
ml/tone/tune_thresholds.py was implemented to systematically search combinations of arousal and valence thresholds.

Search tested candidate values from 0.05 to 0.95 in increments of 0.02.

The threshold rules were evaluated using the classifier's actual prediction logic, including the priority order of excited, upset, and calm. This ensured that the search accounted for how one tag's thresholds could affect prediction for another tag.

For each predicted tag:
- Precision = correct predictions / total predictiosn receiving that tag.
- Coverage = recordings receiving that tag / total recordings.

The search prioritized the threshold combination with the highest coverage while maintaining at least 80% precision on the tuning set.

If no threshold combination met the precision requirement, the existing thresholds were retained for that tag.

## Selected Thresholds
- Excited: Arousal = 0.43 and Valence = 0.51
- Upset: Arousal = 0.41 and Valence = 0.37
- Calm: No combination met the 80% requirement

The excited and upset thresholds met the minimum precision requirement on the tuning set. However, no qualifying calm threshold combination was found.

## Tuning Set Results
The selected thresholds were evaluated on the same 150 recordings used for threshold selection.
1. Excited
    - Predicted: 11
    - Correct: 9
    - Precision: 81.8%
    - Coverage: 7.3%
2. Upset
    - Predicted: 35
    - Correct: 28
    - Precision: 80.0%
    - Coverage: 23.3%
3. Calm
    - Predicted: 6
    - Correct: 0
    - Precision: 0%
    - Coverage: 4%
4. Untagged
    - Predicted: 98
    - Correct: 46
    - Precision: 46.9%
    - Coverage: 65.3%

Excited and upset reached the 80% precision requirement on the tuning set. However, their coverage was limited. Only 11 of 150 recordings received an excited tag, while 35 received an upset tag.

The calm results reflect the existing calm thresholds, which were retained because no qualifying alternative was found. None of the six recordings assigned calm was actually labeled calm.

These results demonstrate the tradeoff between precision and coverage. Even when the search achieved the desired precision for excited and upset, it could only confidently assign those tags to a portion of the recordings.

## Held-Out Results
The existing production thresholds and newly selected thresholds were evaluated on the same 150 held-out recordings

Current production thresholds:
1. Excited
    - Predicted: 11
    - Correct: 4
    - Precision: 36.4%
    - Coverage: 7.3%
2. Upset
    - Predicted: 30
    - Correct: 19
    - Precision: 63.3%
    - Coverage: 20.0%
3. Calm
    - Predicted: 7
    - Correct: 0
    - Precision: 0%
    - Coverage: 4.7%
4. Untagged
    - Predicted: 102
    - Correct: 48
    - Precision: 47.1%
    - Coverage: 68.0%

Tuned thresholds:
1. Excited
    - Predicted: 13
    - Correct: 8
    - Precision: 61.5%
    - Coverage: 8.7%
2. Upset
    - Predicted: 27
    - Correct: 17
    - Precision: 63.0%
    - Coverage: 18.0%
3. Calm
    - Predicted: 6
    - Correct: 0
    - Precision: 0%
    - Coverage: 4.0%
4. Untagged
    - Predicted: 104
    - Correct: 47
    - Precision: 45.2%
    - Coverage: 69.3%

Although the tuned thresholds improved excited precision compared with the existing production thresholds, neither excited nor upset maintained the required 80% precision on the held-out recordings.

Excited precision decreased from 81.8% on the tuning set to 61.5% on held-out data. Upset precision decreased from 80.0% to 63.0%.

Calm remained unreliable, with zero correct predictions among the six held-out recordings receiving that tag.

Coverage also remained limited. The tuned classifier assigned excited to 8.7% of held-out recordings and upset to 18.0%. Most recordings remained untagged.

## Findings and Discussion
The results indicate that the threshold combinations selected using one group of speakers did not generalize reliably to unseen speakers.

Although the search identified excited and upset thresholds that met the 80% precision requirement on the tuning set, their held-out precision fell below the target. This suggests that the relationship between arousal, valence, and the intended emotion labels varies across speakers.

The experiment also revealed a precision and coverage tradeoff. The search was designed to maximize coverage while maintaining at least 80% precision. However, even on the tuning set, only 7.3% of recordings received an excited tag and 23.3% received an upset tag. On held-out data, neither tag maintained the required precision.

This means the classifier faces two limitations:

It cannot consistently maintain the desired precision on unseen speakers.

It assigns tags to a relatively small proportion of recordings when prioritizing prediction reliability.

The score visualizations also showed substantial overlap between the emotion categories. This limits how reliably a classifier based only on fixed arousal and valence boundaries can distinguish the intended tags.

## Recommendations

Excited and upset: Do not replace the existing production thresholds with the experimental thresholds at this stage. Although the experimental thresholds improved excited precision on held-out data, neither tag reached the required 80% precision. Their limited coverage also means that many recordings remain untagged. Further evaluation and potentially a different classification approach may be necessary.

Calm: Recommend withholding automatic calm classification pending UI/UX feedback. No threshold combination met the 80% precision requirement on the tuning set, and none of the held-out calm predictions was correct. The overlap between calm and neutral recordings also makes this distinction difficult using arousal and valence alone.

Production thresholds: Keep the existing production threshold constants unchanged because the experimental thresholds did not demonstrate sufficient held-out precision or coverage to justify replacing them.
