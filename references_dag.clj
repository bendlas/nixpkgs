(ns user
  (:require
   [clojure.java.shell :refer [sh]]
   [clojure.string :as str]
   [clojure.java.io :as io]))

(defn shell-output-lines [{:keys [out err exit] :as rec}]
  (if (zero? exit)
    (remove str/blank? (str/split out #"\n"))
    (throw (ex-info "Non-zero exit" rec))))

(comment
 (defn print-references [seen ref]
   (if (contains? seen ref)
     seen
     (reduce (fn [seen child-ref]
               (println (str "  \"" ref "\" -> \"" child-ref "\";"))
               (print-references seen child-ref))
             (conj seen ref)
             (shell-output-lines (sh "nix-store" "-q" "--references" ref)))))

 (println "strict digraph {")
 (println "  rankdir=LR;")
 (print-references #{} (first (shell-output-lines (apply sh "nix-instantiate" *command-line-args*))))
 (println "}")
 (System/exit 0))

(defn print-references [want]
  (doseq [ref want]
    (transduce
     (filter #(contains? want %))
     (completing
      (fn [_ child-ref]
        (println (str "  \"" ref "\" -> \"" child-ref "\";"))))
     nil
     (shell-output-lines (sh "nix-store" "-q" "--references" ref)))))

(let [ls (line-seq (io/reader *in*))
      wants (into #{}
                  (comp
                   (take-while #(str/starts-with? % "  "))
                   (map str/trim))
                  (drop 2 ls))]
  (assert (= "building the system configuration..." (first ls)))
  (assert (= "these derivations will be built:" (second ls)))

  (println "strict digraph {")
  (println "  rankdir=LR;")
  (print-references wants)
  (println "}")
  (System/exit 0))
