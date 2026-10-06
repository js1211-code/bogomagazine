package com.bogomagazine.modules.layout.api;

import java.util.Set;

/** 경고 코드와 미배치 사유 (docs/composition-engine-api.md 9장). */
public final class Codes {
    private Codes() {}

    public static final String LOW_RES = "low_res";
    public static final String TEXT_OVERFLOW = "text_overflow";
    public static final String CROP_CUTS_SALIENCY = "crop_cuts_saliency";
    public static final String PAGE_PADDED = "page_padded";
    public static final String CORNER_OVERFLOW = "corner_overflow";
    public static final String EMPTY_PAGE = "empty_page";

    public static final Set<String> WARNINGS = Set.of(
            LOW_RES, TEXT_OVERFLOW, CROP_CUTS_SALIENCY, PAGE_PADDED, CORNER_OVERFLOW, EMPTY_PAGE);

    /** 한 면보다 큰 덩어리라 어떤 면에도 못 들어감 */
    public static final String NO_SLOT_FIT = "no_slot_fit";
    /** 최대 쪽수에 도달해 더 넣을 면이 없음 */
    public static final String PAGE_LIMIT = "page_limit";
}
