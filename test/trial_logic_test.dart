import 'package:flutter_test/flutter_test.dart';
import 'package:meu_filho_seguro/services/trial_service.dart';

/// Testes da lógica pura do trial (v17) — sem Firebase, sem aparelho.
///
/// Cobrem: cálculo de dias restantes, determinação de estado,
/// formatação do número do teste e normalização de WhatsApp.
void main() {
  group('TrialService.daysRemainingFor', () {
    test('7 dias restantes no instante do início', () {
      final start = DateTime.utc(2026, 10, 13, 12, 0, 0);
      expect(
        TrialService.daysRemainingFor(
            trialStartUtc: start, nowUtc: start),
        7,
      );
    });

    test('3 dias restantes após 4 dias decorridos', () {
      final start = DateTime.utc(2026, 10, 13, 12);
      final now = DateTime.utc(2026, 10, 17, 12);
      expect(
        TrialService.daysRemainingFor(
            trialStartUtc: start, nowUtc: now),
        3,
      );
    });

    test('0 dia no 7º dia exato (limite)', () {
      final start = DateTime.utc(2026, 10, 13, 12);
      final now = DateTime.utc(2026, 10, 20, 12);
      expect(
        TrialService.daysRemainingFor(
            trialStartUtc: start, nowUtc: now),
        0,
      );
    });

    test('negativo após expirar (8 dias)', () {
      final start = DateTime.utc(2026, 10, 13, 12);
      final now = DateTime.utc(2026, 10, 21, 12);
      expect(
        TrialService.daysRemainingFor(
            trialStartUtc: start, nowUtc: now),
        -1,
      );
    });

    test('horas parciais não contam dia cheio (6d23h → 1 restante)', () {
      final start = DateTime.utc(2026, 10, 13, 12);
      final now = DateTime.utc(2026, 10, 20, 11);
      expect(
        TrialService.daysRemainingFor(
            trialStartUtc: start, nowUtc: now),
        1,
      );
    });
  });

  group('TrialService.statusFor', () {
    test('7, 3 e 1 dia → active', () {
      expect(TrialService.statusFor(7), TrialStatus.active);
      expect(TrialService.statusFor(3), TrialStatus.active);
      expect(TrialService.statusFor(1), TrialStatus.active);
    });

    test('0 e negativo → expired', () {
      expect(TrialService.statusFor(0), TrialStatus.expired);
      expect(TrialService.statusFor(-5), TrialStatus.expired);
    });
  });

  group('TrialService.displayNumber / docIdFor', () {
    test('14 → #014 e doc "0014"', () {
      expect(TrialService.displayNumber(14), '#014');
      expect(TrialService.docIdFor(14), '0014');
    });

    test('1 → #001', () {
      expect(TrialService.displayNumber(1), '#001');
    });

    test('1024 → #1024 (não trunca)', () {
      expect(TrialService.displayNumber(1024), '#1024');
      expect(TrialService.docIdFor(1024), '1024');
    });
  });

  group('TrialService.digitsOnly', () {
    test('remove máscara', () {
      expect(TrialService.digitsOnly('(21) 96958-4287'), '21969584287');
      expect(
          TrialService.digitsOnly('+55 21 96958-4287'), '5521969584287');
    });

    test('vazio → vazio', () {
      expect(TrialService.digitsOnly(''), '');
    });
  });
}
