# NT547 - LAB 06 - BÁO CÁO (TỰ ĐIỀN)

**MSSV:** 23521803  | **Họ tên:** Lê Vọng | **Lớp:** NT547.R11.ANTT
**Session code tự sinh:** SC-93224C | **Tên contract:** StakingPool_1803
**Solidity / Slither:** 0.8.24 / 0.11.6 | **Ngày hoàn thành:** 2026-11-20
**URL GitHub repository:** https://github.com/LeVong123/NT547-Lab06-23521803

## 1. Static scan (2,0 điểm)

- Lệnh raw: `python tools/scan.py --mode raw --tag before`
- Số lượng finding raw từ `evidence/before_raw/summary.json`:
  - High: 4; Medium: 1; Low: 1; Informational: 5; Optimization: 0 (tổng 11 finding)
- Chạy configured: `python tools/scan.py --mode configured --tag before`
- So sánh raw/configured: configured còn 5 finding (High 4, Medium 1); loại 1 Low và 5 Informational. Không có High/Medium biến mất khi chỉ đổi config.
- 3 detector **khác tên**: `weak-prng`, `encode-packed-collision`, `tx-origin`.

| ID finding | Detector | Impact | Confidence | Source (file:dòng) | Luồng dữ liệu: đầu vào -> thao tác -> tác hại |
|---|---|---|---|---|---|
| F01 | `weak-prng` | High | Medium | `AuditTarget.sol:settle`, dòng 56-63 (biểu thức 58) | Người chơi gọi `enter()` và gửi 0.01 ETH -> `settle()` chọn chỉ số bằng `block.timestamp % participants.length` -> người tạo block có thể ảnh hưởng kết quả chọn người thắng và khoản thanh toán. |
| F02 | `encode-packed-collision` | High | High | `AuditTarget.sol:redeemCode`, dòng 83-88 (biểu thức 84) | Người gọi cung cấp hai chuỗi `campaign`, `code` -> `abi.encodePacked` nối hai chuỗi động không có ranh giới rồi băm -> hai cặp khác nhau có thể dùng chung khóa `claimedKeys`, khiến một cặp bị coi là đã dùng sau khi cặp kia claim; mapping vẫn chặn dùng lại cùng khóa. |
| F03 | `tx-origin` | Medium | Medium | `AuditTarget.sol:updateOwner`, dòng 90-94 (điều kiện 91) | Chủ sở hữu bị dụ gọi hợp đồng trung gian do kẻ tấn công kiểm soát -> `tx.origin` vẫn là chủ sở hữu nên kiểm tra qua, dù `msg.sender` là hợp đồng trung gian -> hàm đổi `owner` sang địa chỉ do kẻ tấn công chọn. |

## 2. Triage và sửa lỗi (2,5 điểm)

Đọc toàn bộ AuditTarget.sol: nhận diện **4 mẫu lỗi thật + 2 đoạn cần đánh giá ngữ cảnh**,
kể cả khi Slither không hiển thị đủ 6 cảnh báo. Với mẫu không có detector,
ghi “Manual review / Not reported”, KHÔNG sửa slither.json hoặc tạo finding giả.

| Detector + vị trí | TP / FP / Chưa kết luận | Bằng chứng kiểm soát/khả năng khai thác | Biện pháp (Fix / Accept có lý do) | Sau sửa |
|---|---|---|---|---|
| `weak-prng` — `settle`, dòng 58 | TP | Baseline dùng timestamp để quyết định người nhận toàn bộ ETH; người tạo block có thể ảnh hưởng thời điểm và owner có thể trì hoãn settle. | Fix: dùng coordinator randomness bất đồng bộ; lưu request ID và khóa lượt chơi trước khi gọi coordinator, chỉ chấp nhận callback từ đúng coordinator/request. Kết quả được ghi thành `prizeCredit` để người thắng tự rút. Coordinator phải là dịch vụ randomness có thể tin cậy; đây là giao diện mẫu cho bài lab, chưa deploy. | Đã sửa; không còn `weak-prng` trong raw after. |
| `encode-packed-collision` — `redeemCode`, dòng 84 | TP | Hai chuỗi động được nối không phân cách trước khi băm; cặp chuỗi khác nhau có thể tạo cùng ID, khiến khóa dùng một lần của cặp này chặn cặp kia. Không kết luận rằng có thể dùng lại cùng một ID vì `claimedKeys[id]` vẫn chặn lần hai. | Fix: dùng `keccak256(abi.encode(campaign, code))`, giữ ranh giới giữa hai giá trị trước khi băm. | Đã sửa; không còn detector này trong raw after. |
| `reentrancy-eth` — `redeemSafe`, dòng 71 | Accepted / contextual | `redeemSafe` và `saveSafe` dùng `exclusive`, nên callback không thể gọi lại các entrypoint đó để rút lặp `held`. Finding baseline là rủi ro tiềm năng do ghi state sau call; mutex đã chặn đường khai thác qua hai hàm này. | Giữ mutex và áp dụng Checks-Effects-Interactions: xóa `held[msg.sender]` trước external call; prize dùng pull-payment và xóa credit trước khi gửi. Đồng thời lưu request ID trước lời gọi coordinator để không ghi state sau external call. | Đã harden; `reentrancy-eth` không còn trong raw after. |
| `suicidal` — `destroyPool`, dòng 47-49 | TP | Baseline không có `onlyOwner`; bất kỳ địa chỉ nào cũng có thể gọi và chuyển ETH còn lại cho caller. Sau Cancun/EIP-6780, không khẳng định code/storage bị xóa trong trường hợp thông thường; việc chuyển ETH vẫn có thể xảy ra. | Fix: thêm `onlyOwner`. Quyền đóng pool vẫn là quyền đặc biệt của owner và có thể chuyển ETH cho owner; không mô tả hành vi như xóa toàn bộ contract trên Cancun trở đi. | Đã sửa; không còn `suicidal` trong raw after. |
| `tx-origin` — `updateOwner`, dòng 91 | TP | Nếu owner bị dụ gọi contract trung gian, `tx.origin` vẫn là owner trong khi `msg.sender` là contract đó; contract trung gian có thể gọi `updateOwner(attacker)` để chiếm quyền quản trị. | Fix: dùng modifier `onlyOwner` kiểm tra `msg.sender == owner`; phát event `OwnershipTransferred` khi đổi owner. | Đã sửa; không còn `tx-origin` trong raw after. |
| `timestamp` — `vestStep`, dòng 77 | Accepted / contextual | Đây là cooldown một ngày trong hàm `onlyOwner`, không dùng timestamp để chọn ngẫu nhiên hay cấp quyền; sai lệch ở ranh giới có thể ảnh hưởng thời điểm gọi nhưng không bỏ qua quyền owner. | Giữ cooldown; đặt suppression đúng detector `timestamp` ngay tại phép so sánh và ghi comment rằng timestamp chỉ điều khiển thời gian chờ. Không áp dụng suppression cho finding có thể khai thác. | Raw after không còn Low; suppression có giải thích tại đúng dòng. |

- Kịch bản khai thác TP: owner bị dụ gọi contract trung gian do kẻ tấn công kiểm soát -> contract trung gian gọi `updateOwner(attacker)` khi `tx.origin == owner` -> state `owner` đổi sang địa chỉ attacker -> attacker chiếm quyền quản trị.
- Finding `reentrancy-eth` ban đầu bị giảm khả năng khai thác bởi mutex `exclusive`; vẫn harden theo Checks-Effects-Interactions để cập nhật state trước call. Finding `reentrancy-benign` tạm xuất hiện khi request randomness ghi request ID sau external call; đã đổi thứ tự để ghi request ID trước call và raw after không còn detector reentrancy.
- Bằng chứng after: raw `evidence/after_raw/summary.json` có High 0, Medium 0, Low 0, Informational 5, Optimization 0 (tổng 5); configured `evidence/after_configured/summary.json` có 0 finding. `evidence/after_diff.patch` lưu diff source và công cụ scan. Cả hai thư mục after đều có đủ 4 file.
- 5 Informational còn lại: 4 `low-level-calls` đều kiểm tra `ok` bằng `require` sau lời gọi ETH; 1 `naming-convention` do giữ tên contract theo MSSV. Đây không phải High/Medium và không bị ẩn khỏi cấu hình bằng exclusion bổ sung. Suppression duy nhất là `timestamp` Low tại cooldown `vestStep`, có comment tại đúng vị trí; cấu hình không loại High/Medium.

## 3. Kiến trúc / Inheritance (1,5 điểm)

- Lệnh printer đã chạy: `python tools/print_arch.py`; script gọi `slither contracts/ArchitectureDemo.sol --print human-summary ...` và `slither contracts/ArchitectureDemo.sol --print inheritance-graph ...`.
- Bằng chứng: `evidence/architecture/human_summary.txt`, `printer_log.txt`, `ArchitectureDemo.sol.inheritance-graph.dot` và ảnh `inheritance.png` (Graphviz).
- Access control nằm ở `AccessManaged` (`admin`, modifier `onlyAdmin`); logic số dư nằm ở `BalanceLedger` (`balances`, `balanceOf`, `_credit`); contract triển khai hai phần đó là `StudentAsset`, trong đó `mint` được bảo vệ bởi `onlyAdmin`.
- Sơ đồ cho thấy `StudentAsset` kế thừa đồng thời `AccessManaged` và `BalanceLedger`. Khi audit, cần kiểm tra constructor có gán đúng `admin` và đường gọi `mint` có bị giới hạn bởi `onlyAdmin`. Tiếp đó kiểm tra `mint` chặn địa chỉ zero, cập nhật số dư qua `_credit` và phát event `Mint`. Cũng cần xem xét các hàm con được kế thừa có thể truy cập `balances` nội bộ ra sao.

## 4. Red -> Green CI (2,5 điểm)

| Phase | Commit (full/short SHA) | Run URL | Kết quả | Detector khiến RED / lý do GREEN |
|---|---|---|---|---|
| Baseline vulnerable | `61ec9c6e1b787c4590b28c9639a69e5e3967790a` | [GitHub Actions run #1](https://github.com/LeVong123/NT547-Lab06-23521803/actions/runs/44736431953) | RED (đúng baseline) | Slither và solc cài thành công, contract biên dịch được; scan phát hiện 5 detector (`weak-prng`, `encode-packed-collision`, `reentrancy-eth`, `suicidal`, `tx-origin`). Configured local summary có High 4 / Medium 1 nên gate `fail-on: medium` làm run RED. |
| Patched | `627cbb6a10a1988fa9cdc338df559787e72e6d69` | [GitHub Actions run #2](https://github.com/LeVong123/NT547-Lab06-23521803/actions/runs/44740547670) | GREEN | Push kích hoạt workflow; run `Lab06 Slither gate` hoàn tất thành công (57s). Local raw: High 0 / Medium 0; configured: 0. |

- So sánh local `--fail-none` (thu thập findings) với CI `fail-on: medium`: ...
- `exclude_low/informational` thay đổi kết quả hiển thị ra sao: ...

## 5. Mutation RED -> GREEN (1,5 điểm)

- Mutation một dòng: `require(msg.sender == owner, "not owner")` -> `require(tx.origin == owner, "not owner")` trong `modifier onlyOwner`.
- Detector kỳ vọng: `tx-origin` (mức Medium); xác nhận của em từ CI: ...

| Phase | Commit SHA | Run URL | Kết quả |
|---|---|---|---|
| Mutation | | | RED |
| Revert mutation | | | GREEN |

- Giải thích sự thay đổi về nguồn định danh/authorization: ...

## 6. Bằng chứng, tự kiểm

- [x] `AuditTarget.sol`, `lab_identity.json`
- [x] `evidence/before_raw/` và `evidence/before_configured/`
- [x] `evidence/after_raw/` và `evidence/after_configured/`
- [x] `evidence/architecture/`
- [ ] 04 URL Actions run RED/GREEN/RED/GREEN + 04 commit SHA
- [ ] Link repo và ảnh màn hình có terminal / URL / commit SHA; không cắt mất ngữ cảnh
- [ ] Các finding được triage, không chép lại mô tả detector thay cho suy luận
- [ ] Tuyệt đối không có seed phrase, private key, credentials

**Nhận xét cuối cùng (5–7 câu):** ...
