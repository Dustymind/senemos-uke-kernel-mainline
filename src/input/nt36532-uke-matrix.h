/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef NT36532_UKE_MATRIX_H
#define NT36532_UKE_MATRIX_H

#include "nt36532-uke-protocol.h"

#define NVT_UKE_ROWS 40
#define NVT_UKE_COLUMNS 60
#define NVT_UKE_CALIBRATION_FRAMES 32
/*
 * Raw Uke multifinger peaks are weaker than the vendor processed-signal scale,
 * so these are not the THP thresholds and must not be copied from them: the
 * stock configuration works on firmware-filtered fixed-point values
 * (`o82_nova_thp_config.ini`: touch_down_threshold 300, mc_peak_thd 220), while
 * this driver works on the raw signed 16-bit matrix.  What carries over is the
 * shape - a low gate decides whether a blob exists at all, and a higher gate
 * decides whether a contact may begin - which is a double threshold, not the
 * usual hysteresis.  Both layers are pinned by tests: `touch-matrix.c` requires
 * a peak of 90 to still produce a blob, `touch-publish.c` requires the same 90
 * not to start a new contact while 120 does.
 */
#define NVT_UKE_PEAK_DOWN 100
#define NVT_UKE_PEAK_UP 70
/*
 * Coordinate jitter locking, converted from the THP configuration.  The touch
 * scale runs at exactly 10 units per display pixel on both axes - 32000 units
 * over the 3200 px long edge, 21360 over the 2136 px short edge, matching the
 * 135 units/mm and 13.5 px/mm the panel geometry gives - so `jitter`
 * first_jitter_lock_dis 30, stable_jitter_lock_dis 8 and
 * first_jitter_stable_frame 25 become the values below.  THP switches from the
 * wide lock to the tight one once a contact has been held that long; a single
 * fixed margin cannot do both, which is why a held finger used to stay clamped
 * and stair-step on a slow drag.
 */
#define NVT_UKE_JITTER_FIRST_LOCK 300
#define NVT_UKE_JITTER_STABLE_LOCK 80
#define NVT_UKE_JITTER_STABLE_FRAMES 25

struct nvt_uke_matrix {
	s32 reference[NVT_UKE_NODES], delta[NVT_UKE_NODES];
	u16 parent[NVT_UKE_NODES];
	u32 columns[NVT_UKE_COLUMNS], rows[NVT_UKE_ROWS];
	unsigned int samples, quiet;
};

void nvt_uke_matrix_reset(struct nvt_uke_matrix *matrix);
int nvt_uke_matrix_process(struct nvt_uke_matrix *matrix,
	const struct nvt_uke_frame *frame, u16 max_x, u16 max_y,
	struct nvt_uke_contacts *contacts);

#endif
