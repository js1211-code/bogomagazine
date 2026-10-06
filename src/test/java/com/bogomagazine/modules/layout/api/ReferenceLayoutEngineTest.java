package com.bogomagazine.modules.layout.api;

/** 기준 엔진으로 계약을 돌린다. 실제 엔진(v0.1)이 생기면 같은 모양의 클래스를 하나 더 둔다. */
class ReferenceLayoutEngineTest extends LayoutEngineContract {
    @Override
    protected LayoutEngine engine() {
        return new ReferenceLayoutEngine();
    }
}
