//
//  GlyphEvolutionEngine.swift
//  GlyphCanvas
//

import Foundation
import os.log
import simd

enum OptimizationMode: String, CaseIterable, Sendable {
    case greedy
    case genetic
}

struct GeneticEvolutionConfig: Sendable {
    var populationSize: Int
    var generations: Int
    /// Top fraction kept as elite parents (e.g. 0.3).
    var eliteFraction: Double
    /// Hard cap on total fitness evaluations (each genome evaluation counts as one).
    var maxEvaluations: Int

    static let `default` = GeneticEvolutionConfig(
        populationSize: 16,
        generations: 8,
        eliteFraction: 0.3,
        maxEvaluations: 128
    )
}

struct EvolutionResult: Sendable {
    var bestGenome: GlyphGenome?
    /// Minimum total loss (perceptual + penalties), for progress metrics (lower better).
    var bestLoss: Double
    var generationsRun: Int
    var evaluationsUsed: Int
    /// Best fitness in the last completed evaluation generation (higher better).
    var bestFitnessLastGeneration: Double
}

enum GlyphEvolutionEngine {
    /// Evolves a population; `evaluateFitness` returns **fitness** (higher better), or `nil` if evaluation failed.
    static func evolve(
        config: GeneticEvolutionConfig,
        seedFromCache: GlyphGenome?,
        region: PixelRegion,
        meanLuminanceY: Double,
        averageFontSize: CGFloat,
        baseRGB: SIMD3<Float>,
        characterPool: [Character],
        stampIsBold: Bool = false,
        evaluateFitness: (GlyphGenome) -> Double?,
        shouldCancel: () -> Bool
    ) -> EvolutionResult {
        let pop = max(4, config.populationSize)
        let ef = min(0.45, max(0.1, config.eliteFraction))
        let eliteCount = max(1, min(pop - 1, Int(Double(pop) * ef)))
        let maxGen = max(
            1,
            min(
                config.generations,
                max(1, config.maxEvaluations / pop)
            )
        )

        var rng = SystemRandomNumberGenerator()

        var population: [GlyphGenome] = (0..<pop).map { _ in
            GlyphGenome.random(
                region: region,
                meanLuminanceY: meanLuminanceY,
                averageFontSize: averageFontSize,
                baseRGB: baseRGB,
                characterPool: characterPool,
                isBold: stampIsBold,
                rng: &rng
            )
        }

        if let seed = seedFromCache {
            let seedSlots = min(3, pop)
            for i in 0..<seedSlots {
                var g = seed
                g.isBold = stampIsBold
                g.mutate(
                    region: region,
                    meanLuminanceY: meanLuminanceY,
                    averageFontSize: averageFontSize,
                    baseRGB: baseRGB,
                    characterPool: characterPool,
                    stampIsBold: stampIsBold,
                    rng: &rng
                )
                population[i] = g
            }
        }

        var bestGenome: GlyphGenome?
        var bestLoss = Double.infinity
        var evaluationsUsed = 0
        var bestFitnessLastGen = -Double.infinity
        var generationsCompleted = 0

        for gen in 0..<maxGen {
            if shouldCancel() {
                break
            }

            var scored: [(GlyphGenome, Double)] = []
            scored.reserveCapacity(pop)

            for g in population {
                if shouldCancel() {
                    return EvolutionResult(
                        bestGenome: bestGenome,
                        bestLoss: bestLoss,
                        generationsRun: generationsCompleted,
                        evaluationsUsed: evaluationsUsed,
                        bestFitnessLastGeneration: bestFitnessLastGen
                    )
                }
                if evaluationsUsed >= config.maxEvaluations {
                    break
                }
                guard let fit = evaluateFitness(g) else { continue }
                evaluationsUsed += 1
                let loss = -fit
                scored.append((g, fit))
                if loss < bestLoss {
                    bestLoss = loss
                    bestGenome = g
                }
            }

            if scored.isEmpty {
                break
            }

            scored.sort { $0.1 > $1.1 }
            bestFitnessLastGen = scored[0].1
            generationsCompleted = gen + 1

            #if DEBUG
            Logger(subsystem: "GlyphCanvas", category: "GA").debug(
                "gen=\(gen + 1)/\(maxGen) bestFitness=\(bestFitnessLastGen) evals=\(evaluationsUsed)"
            )
            #endif

            if gen == maxGen - 1 {
                break
            }
            if evaluationsUsed >= config.maxEvaluations {
                break
            }

            let elite = Array(scored.prefix(eliteCount).map(\.0))
            var next: [GlyphGenome] = elite

            while next.count < pop {
                if shouldCancel() {
                    break
                }
                let p1 = elite.randomElement(using: &rng) ?? elite[0]
                let p2 = elite.randomElement(using: &rng) ?? elite[0]
                var child = GlyphGenome.crossover(p1, p2, rng: &rng)
                child.isBold = stampIsBold
                child.mutate(
                    region: region,
                    meanLuminanceY: meanLuminanceY,
                    averageFontSize: averageFontSize,
                    baseRGB: baseRGB,
                    characterPool: characterPool,
                    stampIsBold: stampIsBold,
                    rng: &rng
                )
                next.append(child)
            }

            population = Array(next.prefix(pop))
        }

        return EvolutionResult(
            bestGenome: bestGenome,
            bestLoss: bestLoss == .infinity ? .infinity : bestLoss,
            generationsRun: generationsCompleted,
            evaluationsUsed: evaluationsUsed,
            bestFitnessLastGeneration: bestFitnessLastGen
        )
    }
}
